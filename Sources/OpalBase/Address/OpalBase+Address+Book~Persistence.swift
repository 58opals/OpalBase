// OpalBase+Address+Book~Persistence.swift

import Foundation
import OpalCrypto

extension _OpalBase.Address.Book {
    init(from snapshot: Snapshot,
         rootExtendedPrivateKey: OpalCrypto.Key.ExtendedPrivate? = nil,
         rootExtendedPublicKey: OpalCrypto.Key.ExtendedPublic? = nil,
         purpose: OpalBase.Key.DerivationPath.Purpose,
         coinType: OpalBase.Key.DerivationPath.CoinType,
         account: OpalBase.Key.DerivationPath.Account,
         gapLimit: Int = 20,
         cacheValidityDuration: TimeInterval = 10 * 60,
         spendReservationExpirationInterval: TimeInterval = 10 * 60) async throws {
        try await self.init(rootExtendedPrivateKey: rootExtendedPrivateKey,
                            rootExtendedPublicKey: rootExtendedPublicKey,
                            purpose: purpose,
                            coinType: coinType,
                            account: account,
                            gapLimit: gapLimit,
                            cacheValidityDuration: cacheValidityDuration,
                            spendReservationExpirationInterval: spendReservationExpirationInterval)
        try await refresh(with: snapshot)
    }

    func makeSnapshot() -> Snapshot {
        let receiving = makeEntrySnapshots(for: .receiving)
        let change = makeEntrySnapshots(for: .change)

        let utxoSnaps = utxoStore.listUTXOs().map {
            Snapshot.UTXO(value: $0.value,
                          lockingScript: $0.lockingScript.hexadecimalString,
                          tokenData: $0.tokenData,
                          transactionHash: $0.previousTransactionHash.naturalOrder.hexadecimalString,
                          outputIndex: $0.previousTransactionOutputIndex)
        }

        let transactionSnaps = transactionLog.listRecords().map { record in
            let chainMetadata = record.chainMetadata
            let confirmationMetadata = record.confirmationMetadata
            let verificationMetadata = record.verificationMetadata
            let tokenDelta = record.tokenDelta
            let proof = verificationMetadata.merkleProof.map { proof in
                Snapshot.Transaction.MerkleProof(
                    blockHeight: proof.blockHeight,
                    position: proof.position,
                    branch: proof.branch.map { $0.hexadecimalString },
                    blockHash: proof.blockHash?.hexadecimalString
                )
            }
            return Snapshot.Transaction(
                transactionHash: record.transactionHash.naturalOrder.hexadecimalString,
                height: chainMetadata.height,
                fee: chainMetadata.fee,
                scriptHashes: Array(chainMetadata.scriptHashes),
                firstSeenAt: chainMetadata.firstSeenAt,
                lastUpdatedAt: chainMetadata.lastUpdatedAt,
                status: record.status,
                confirmationHeight: confirmationMetadata.height,
                confirmedAt: confirmationMetadata.confirmedAt,
                verificationStatus: verificationMetadata.status,
                merkleProof: proof,
                lastVerifiedHeight: verificationMetadata.lastVerifiedHeight,
                lastCheckedAt: verificationMetadata.lastCheckedAt,
                fungibleTokenDeltasByCategory: tokenDelta.fungibleDeltasByCategory,
                nonFungibleTokenAdditions: Array(tokenDelta.nonFungibleTokenAdditions),
                nonFungibleTokenRemovals: Array(tokenDelta.nonFungibleTokenRemovals),
                bchLockedInTokenOutputDelta: tokenDelta.bchLockedInTokenOutputDelta
            )
        }

        return Snapshot(receivingEntries: receiving,
                        changeEntries: change,
                        utxos: utxoSnaps,
                        transactions: transactionSnaps)
    }

    private func makeEntrySnapshots(for usage: OpalBase.Key.DerivationPath.Usage) -> [Snapshot.Entry] {
        inventory.listEntries(for: usage).map { entry in
            Snapshot.Entry(usage: entry.derivationPath.usage,
                           index: entry.derivationPath.index,
                           isUsed: entry.isUsed,
                           isReserved: entry.isReserved,
                           balance: entry.cache.balance?.uint64,
                           lastUpdated: entry.cache.lastUpdated)
        }
    }

    func refresh(with snapshot: Snapshot) async throws {
        try validateEntryUsage(in: snapshot.receivingEntries, expected: .receiving)
        try validateEntryUsage(in: snapshot.changeEntries, expected: .change)
        try validateUniqueEntryIndices(in: snapshot.receivingEntries, usage: .receiving)
        try validateUniqueEntryIndices(in: snapshot.changeEntries, usage: .change)
        try validateEntryBalances(in: snapshot.receivingEntries + snapshot.changeEntries)
        let restoredUTXOs = try makeRestoredUTXOs(from: snapshot.utxos)
        let restoredTransactions = try makeRestoredTransactionRecords(from: snapshot.transactions)

        inventory = .init(cacheValidityDuration: inventory.cacheValidityDuration)
        try await restore(entrySnapshots: snapshot.receivingEntries, usage: .receiving)
        try await restore(entrySnapshots: snapshot.changeEntries, usage: .change)

        utxoStore.replace(with: Set(restoredUTXOs))
        clearSpendReservationState()
        transactionLog.reset()

        for record in restoredTransactions {
            transactionLog.store(record)
        }
    }

    private func validateEntryBalances(in entries: [Snapshot.Entry]) throws {
        for entry in entries {
            guard let balanceValue = entry.balance else { continue }
            do {
                _ = try OpalBase.Satoshi(balanceValue)
            } catch {
                throw OpalBase.Address.Book.Error.invalidSnapshotBalance(value: balanceValue, reason: error)
            }
        }
    }

    private func validateEntryUsage(
        in entries: [Snapshot.Entry],
        expected: OpalBase.Key.DerivationPath.Usage
    ) throws {
        for entry in entries where entry.usage != expected {
            throw OpalBase.Address.Book.Error.invalidSnapshotEntryUsage(
                expected: expected,
                actual: entry.usage,
                index: entry.index
            )
        }
    }

    private func validateUniqueEntryIndices(
        in entries: [Snapshot.Entry],
        usage: OpalBase.Key.DerivationPath.Usage
    ) throws {
        var seenIndices: Set<UInt32> = .init()
        for entry in entries where !seenIndices.insert(entry.index).inserted {
            throw OpalBase.Address.Book.Error.invalidSnapshotDuplicateEntry(
                usage: usage,
                index: entry.index
            )
        }
    }

    private func makeRestoredUTXOs(from snapshots: [Snapshot.UTXO]) throws -> [OpalBase.Transaction.Output.Unspent] {
        var restoredUTXOs: [OpalBase.Transaction.Output.Unspent] = .init()
        restoredUTXOs.reserveCapacity(snapshots.count)
        var seenOutpoints: Set<UTXORepository.Outpoint> = .init()

        for snapshot in snapshots {
            let tokenData = try snapshot.makeTokenData()
            let transactionHashData = try Data(hexadecimalString: snapshot.transactionHash)
            guard transactionHashData.count == OpalBase.Transaction.Hash.expectedByteCount else {
                throw OpalBase.Address.Book.Error.invalidSnapshotTransactionHashLength(
                    expected: OpalBase.Transaction.Hash.expectedByteCount,
                    actual: transactionHashData.count
                )
            }
            let transactionHash = OpalBase.Transaction.Hash(naturalOrder: transactionHashData)
            let utxo = OpalBase.Transaction.Output.Unspent(
                value: snapshot.value,
                lockingScript: try Data(hexadecimalString: snapshot.lockingScript),
                tokenData: tokenData,
                previousTransactionHash: transactionHash,
                previousTransactionOutputIndex: snapshot.outputIndex
            )
            let outpoint = UTXORepository.Outpoint(utxo)
            guard seenOutpoints.insert(outpoint).inserted else {
                throw OpalBase.Address.Book.Error.invalidSnapshotDuplicateUTXO(
                    transactionHash: transactionHash,
                    outputIndex: snapshot.outputIndex
                )
            }
            restoredUTXOs.append(utxo)
        }

        return restoredUTXOs
    }

    private func makeRestoredTransactionRecords(
        from snapshots: [Snapshot.Transaction]
    ) throws -> [OpalBase.Transaction.History.Record] {
        var seenTransactionHashes: Set<OpalBase.Transaction.Hash> = .init()
        return try snapshots.map { transaction in
            let hashData = try Data(hexadecimalString: transaction.transactionHash)
            guard hashData.count == OpalBase.Transaction.Hash.expectedByteCount else {
                throw OpalBase.Address.Book.Error.invalidSnapshotTransactionHashLength(
                    expected: OpalBase.Transaction.Hash.expectedByteCount,
                    actual: hashData.count
                )
            }
            let hash = OpalBase.Transaction.Hash(naturalOrder: hashData)
            guard seenTransactionHashes.insert(hash).inserted else {
                throw OpalBase.Address.Book.Error.invalidSnapshotDuplicateTransaction(hash)
            }
            try validateScriptHashes(in: transaction.scriptHashes)
            let proof = try transaction.merkleProof.map { proof -> OpalBase.Transaction.MerkleProof in
                let branch = try proof.branch.map { branchNode -> Data in
                    let data = try Data(hexadecimalString: branchNode)
                    guard data.count == OpalBase.Transaction.Hash.expectedByteCount else {
                        throw OpalBase.Address.Book.Error.invalidSnapshotMerkleProofHashLength(
                            expected: OpalBase.Transaction.Hash.expectedByteCount,
                            actual: data.count
                        )
                    }
                    return data
                }
                let blockHash = try proof.blockHash.map { blockHash -> Data in
                    let data = try Data(hexadecimalString: blockHash)
                    guard data.count == OpalBase.Transaction.Hash.expectedByteCount else {
                        throw OpalBase.Address.Book.Error.invalidSnapshotMerkleProofHashLength(
                            expected: OpalBase.Transaction.Hash.expectedByteCount,
                            actual: data.count
                        )
                    }
                    return data
                }
                return OpalBase.Transaction.MerkleProof(
                    blockHeight: proof.blockHeight,
                    position: proof.position,
                    branch: branch,
                    blockHash: blockHash
                )
            }
            if transaction.verificationStatus == .verified && proof == nil {
                throw OpalBase.Address.Book.Error.invalidSnapshotVerificationState
            }
            if transaction.status == .confirmed && transaction.confirmationHeight == nil {
                throw OpalBase.Address.Book.Error.invalidSnapshotConfirmationState
            }
            let chainMetadata = OpalBase.Transaction.History.Record.ChainMetadata(height: transaction.height,
                                                                         fee: transaction.fee,
                                                                         scriptHashes: Set(transaction.scriptHashes),
                                                                         firstSeenAt: transaction.firstSeenAt,
                                                                         lastUpdatedAt: transaction.lastUpdatedAt)
            let confirmationMetadata = OpalBase.Transaction.History.Record.ConfirmationMetadata(height: transaction.confirmationHeight,
                                                                                       confirmedAt: transaction.confirmedAt)
            let verificationMetadata = OpalBase.Transaction.History.Record.VerificationMetadata(status: transaction.verificationStatus,
                                                                                       merkleProof: proof,
                                                                                       lastVerifiedHeight: transaction.lastVerifiedHeight,
                                                                                       lastCheckedAt: transaction.lastCheckedAt)
            let tokenDelta = OpalBase.Transaction.History.Record.TokenDelta(
                fungibleDeltasByCategory: transaction.fungibleTokenDeltasByCategory ?? .init(),
                nonFungibleTokenAdditions: Set(transaction.nonFungibleTokenAdditions ?? .init()),
                nonFungibleTokenRemovals: Set(transaction.nonFungibleTokenRemovals ?? .init()),
                bchLockedInTokenOutputDelta: transaction.bchLockedInTokenOutputDelta ?? 0
            )
            let record = OpalBase.Transaction.History.Record(transactionHash: hash,
                                                    status: transaction.status,
                                                    chainMetadata: chainMetadata,
                                                    confirmationMetadata: confirmationMetadata,
                                                    verificationMetadata: verificationMetadata,
                                                    tokenDelta: tokenDelta)
            return record
        }
    }

    private func validateScriptHashes(in scriptHashes: [String]) throws {
        guard !scriptHashes.isEmpty else {
            throw OpalBase.Address.Book.Error.invalidSnapshotMissingScriptHashes
        }
        for scriptHash in scriptHashes {
            let data = try Data(hexadecimalString: scriptHash)
            guard data.count == OpalBase.Transaction.Hash.expectedByteCount else {
                throw OpalBase.Address.Book.Error.invalidSnapshotScriptHashLength(
                    expected: OpalBase.Transaction.Hash.expectedByteCount,
                    actual: data.count
                )
            }
        }
    }

    private func restore(entrySnapshots: [Snapshot.Entry], usage: OpalBase.Key.DerivationPath.Usage) async throws {
        if let highestIndex = entrySnapshots.map(\.index).max() {
            let entryCount = Int(highestIndex) + 1
            try await generateEntries(for: usage,
                                      numberOfNewEntries: entryCount,
                                      isUsed: false,
                                      shouldNotifyNewEntries: false)
        }

        for snapshotEntry in entrySnapshots {
            let restoredBalance: OpalBase.Satoshi?
            if let balanceValue = snapshotEntry.balance {
                do {
                    restoredBalance = try OpalBase.Satoshi(balanceValue)
                } catch {
                    throw OpalBase.Address.Book.Error.invalidSnapshotBalance(value: balanceValue, reason: error)
                }
            } else {
                restoredBalance = nil
            }

            inventory.updateEntry(at: Int(snapshotEntry.index), usage: usage) { entry in
                entry.isUsed = snapshotEntry.isUsed
                entry.isReserved = snapshotEntry.isReserved
                entry.cache.balance = restoredBalance
                entry.cache.lastUpdated = snapshotEntry.lastUpdated
            }
        }

        let numberOfMissingUnusedEntries = gapLimit - inventory.countUnusedEntries(for: usage)
        if numberOfMissingUnusedEntries > 0 {
            try await generateEntries(for: usage,
                                      numberOfNewEntries: numberOfMissingUnusedEntries,
                                      isUsed: false,
                                      shouldNotifyNewEntries: false)
        }
    }
}
