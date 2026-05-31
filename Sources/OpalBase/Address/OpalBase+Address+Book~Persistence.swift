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

        let unspentOutputSnapshots = utxoStore.listUTXOs().map {
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
                        utxos: unspentOutputSnapshots,
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
        let entrySnapshots = snapshot.receivingEntries + snapshot.changeEntries
        try validateEntryUsage(in: snapshot.receivingEntries, expected: .receiving)
        try validateEntryUsage(in: snapshot.changeEntries, expected: .change)
        try validateEntryReservationState(in: entrySnapshots)
        for entry in entrySnapshots where entry.index > HardenedIndex.maxUnhardenedValue {
            throw OpalBase.Address.Book.Error.indexOutOfBounds
        }
        try validateUniqueEntryIndices(in: snapshot.receivingEntries, usage: .receiving)
        try validateUniqueEntryIndices(in: snapshot.changeEntries, usage: .change)
        let restoredEntryBalances = try makeRestoredEntryBalances(in: entrySnapshots)
        let restoredEntryReferences = try makeRestoredEntryReferences(
            from: entrySnapshots
        )
        let restoredUTXOs = try makeRestoredUTXOs(
            from: snapshot.utxos,
            restoredEntryLockingScripts: restoredEntryReferences.lockingScripts
        )
        let restoredTransactions = try makeRestoredTransactionRecords(
            from: snapshot.transactions,
            restoredEntryScriptHashes: restoredEntryReferences.scriptHashes
        )

        inventory = .init(cacheValidityDuration: inventory.cacheValidityDuration)
        try await restore(
            entrySnapshots: snapshot.receivingEntries,
            usage: .receiving,
            restoredEntryBalances: restoredEntryBalances[.receiving] ?? [:]
        )
        try await restore(
            entrySnapshots: snapshot.changeEntries,
            usage: .change,
            restoredEntryBalances: restoredEntryBalances[.change] ?? [:]
        )

        utxoStore.replace(with: Set(restoredUTXOs))
        clearSpendReservationState()
        transactionLog.reset()

        for record in restoredTransactions {
            transactionLog.store(record)
        }
    }

    private func makeRestoredEntryBalances(in entries: [Snapshot.Entry]) throws -> RestoredEntryBalances {
        var restoredEntryBalances: RestoredEntryBalances = [:]

        for entry in entries {
            guard let balanceValue = entry.balance else { continue }
            do {
                restoredEntryBalances[entry.usage, default: [:]][entry.index] = try OpalBase.Satoshi(balanceValue)
            } catch {
                throw OpalBase.Address.Book.Error.invalidSnapshotBalance(value: balanceValue, reason: error)
            }
        }

        return restoredEntryBalances
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

    private func validateEntryReservationState(in entries: [Snapshot.Entry]) throws {
        for entry in entries where entry.isReserved && !entry.isUsed {
            throw OpalBase.Address.Book.Error.invalidSnapshotEntryReservationState(
                usage: entry.usage,
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

    private func makeRestoredEntryReferences(
        from entries: [Snapshot.Entry]
    ) throws -> (lockingScripts: Set<Data>, scriptHashes: Set<String>) {
        var lockingScripts: Set<Data> = .init()
        var scriptHashes: Set<String> = .init()
        lockingScripts.reserveCapacity(entries.count)
        scriptHashes.reserveCapacity(entries.count)

        for entry in entries {
            let address = try generateAddress(at: entry.index, for: entry.usage)
            lockingScripts.insert(address.lockingScript.data)
            scriptHashes.insert(address.makeScriptHash().hexadecimalString)
        }

        return (lockingScripts, scriptHashes)
    }

    private func makeRestoredUTXOs(
        from snapshots: [Snapshot.UTXO],
        restoredEntryLockingScripts: Set<Data>
    ) throws -> [OpalBase.Transaction.Output.Unspent] {
        var restoredUTXOs: [OpalBase.Transaction.Output.Unspent] = .init()
        restoredUTXOs.reserveCapacity(snapshots.count)
        var seenOutpoints: Set<UTXORepository.Outpoint> = .init()

        for snapshot in snapshots {
            do {
                _ = try OpalBase.Satoshi(snapshot.value)
            } catch {
                throw OpalBase.Address.Book.Error.invalidSnapshotBalance(
                    value: snapshot.value,
                    reason: error
                )
            }
            let tokenData = try snapshot.makeTokenData()
            let transactionHashData = try makeSnapshotTransactionHashData(from: snapshot.transactionHash)
            let lockingScript = try makeSnapshotUTXOLockingScriptData(from: snapshot.lockingScript)
            guard restoredEntryLockingScripts.contains(lockingScript) else {
                throw OpalBase.Address.Book.Error.invalidSnapshotUTXOLockingScript(lockingScript)
            }
            let transactionHash = OpalBase.Transaction.Hash(naturalOrder: transactionHashData)
            let utxo = OpalBase.Transaction.Output.Unspent(
                value: snapshot.value,
                lockingScript: lockingScript,
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
        from snapshots: [Snapshot.Transaction],
        restoredEntryScriptHashes: Set<String>
    ) throws -> [OpalBase.Transaction.History.Record] {
        var seenTransactionHashes: Set<OpalBase.Transaction.Hash> = .init()
        return try snapshots.map { transaction in
            let hashData = try makeSnapshotTransactionHashData(from: transaction.transactionHash)
            let hash = OpalBase.Transaction.Hash(naturalOrder: hashData)
            guard seenTransactionHashes.insert(hash).inserted else {
                throw OpalBase.Address.Book.Error.invalidSnapshotDuplicateTransaction(hash)
            }
            if let fee = transaction.fee {
                do {
                    _ = try OpalBase.Satoshi(fee)
                } catch {
                    throw OpalBase.Address.Book.Error.invalidSnapshotFee(
                        value: fee,
                        reason: error
                    )
                }
            }
            let scriptHashes = try validateScriptHashes(
                in: transaction.scriptHashes,
                restoredEntryScriptHashes: restoredEntryScriptHashes
            )
            let proof = try transaction.merkleProof.map(makeRestoredMerkleProof)
            if transaction.verificationStatus == .verified {
                guard let proof,
                      transaction.status == .confirmed,
                      let confirmationHeight = transaction.confirmationHeight,
                      UInt64(proof.blockHeight) == confirmationHeight,
                      transaction.lastVerifiedHeight != nil,
                      transaction.lastCheckedAt != nil else {
                    throw OpalBase.Address.Book.Error.invalidSnapshotVerificationState
                }
            }
            switch transaction.status {
            case .confirmed:
                guard let confirmationHeight = transaction.confirmationHeight,
                      transaction.confirmedAt != nil,
                      let chainHeight = UInt64(exactly: transaction.height),
                      chainHeight == confirmationHeight else {
                    throw OpalBase.Address.Book.Error.invalidSnapshotConfirmationState
                }
            case .discovered, .pending, .failed:
                if transaction.height > 0 ||
                    transaction.confirmationHeight != nil ||
                    transaction.confirmedAt != nil {
                    throw OpalBase.Address.Book.Error.invalidSnapshotConfirmationState
                }
            }
            let chainMetadata = OpalBase.Transaction.History.Record.ChainMetadata(height: transaction.height,
                                                                         fee: transaction.fee,
                                                                         scriptHashes: Set(scriptHashes),
                                                                         firstSeenAt: transaction.firstSeenAt,
                                                                         lastUpdatedAt: transaction.lastUpdatedAt)
            let confirmationMetadata = OpalBase.Transaction.History.Record.ConfirmationMetadata(height: transaction.confirmationHeight,
                                                                                       confirmedAt: transaction.confirmedAt)
            let verificationMetadata = OpalBase.Transaction.History.Record.VerificationMetadata(status: transaction.verificationStatus,
                                                                                       merkleProof: proof,
                                                                                       lastVerifiedHeight: transaction.lastVerifiedHeight,
                                                                                       lastCheckedAt: transaction.lastCheckedAt)
            let nonFungibleTokenAdditions = try validateUniqueTokenDeltas(
                in: transaction.nonFungibleTokenAdditions ?? .init()
            )
            let nonFungibleTokenRemovals = try validateUniqueTokenDeltas(
                in: transaction.nonFungibleTokenRemovals ?? .init()
            )
            let fungibleTokenDeltas = try validateSnapshotFungibleTokenDeltas(
                transaction.fungibleTokenDeltasByCategory ?? .init()
            )
            let bchLockedInTokenOutputDelta = try validateSnapshotLockedBCHDelta(
                transaction.bchLockedInTokenOutputDelta ?? 0
            )
            let tokenDelta = OpalBase.Transaction.History.Record.TokenDelta(
                fungibleDeltasByCategory: fungibleTokenDeltas,
                nonFungibleTokenAdditions: nonFungibleTokenAdditions,
                nonFungibleTokenRemovals: nonFungibleTokenRemovals,
                bchLockedInTokenOutputDelta: bchLockedInTokenOutputDelta
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

    private func makeSnapshotTransactionHashData(from transactionHash: String) throws -> Data {
        guard !hasHexadecimalPrefix(transactionHash) else {
            throw OpalBase.Address.Book.Error.invalidSnapshotTransactionHash(transactionHash)
        }
        let hashData = try Data(hexadecimalString: transactionHash)
        guard hashData.count == OpalBase.Transaction.Hash.expectedByteCount else {
            throw OpalBase.Address.Book.Error.invalidSnapshotTransactionHashLength(
                expected: OpalBase.Transaction.Hash.expectedByteCount,
                actual: hashData.count
            )
        }
        return hashData
    }

    private func makeSnapshotUTXOLockingScriptData(from lockingScript: String) throws -> Data {
        guard !hasHexadecimalPrefix(lockingScript) else {
            throw OpalBase.Address.Book.Error.invalidSnapshotUTXOLockingScriptHex(lockingScript)
        }
        return try Data(hexadecimalString: lockingScript)
    }

    private func makeSnapshotMerkleProofHashData(from hash: String) throws -> Data {
        guard !hasHexadecimalPrefix(hash) else {
            throw OpalBase.Address.Book.Error.invalidSnapshotMerkleProofHash(hash)
        }
        let data = try Data(hexadecimalString: hash)
        guard data.count == OpalBase.Transaction.Hash.expectedByteCount else {
            throw OpalBase.Address.Book.Error.invalidSnapshotMerkleProofHashLength(
                expected: OpalBase.Transaction.Hash.expectedByteCount,
                actual: data.count
            )
        }
        return data
    }

    private func makeRestoredMerkleProof(
        from proof: Snapshot.Transaction.MerkleProof
    ) throws -> OpalBase.Transaction.MerkleProof {
        let branch = try proof.branch.map { branchNode -> Data in
            try makeSnapshotMerkleProofHashData(from: branchNode)
        }
        let blockHash = try proof.blockHash.map { blockHash -> Data in
            try makeSnapshotMerkleProofHashData(from: blockHash)
        }
        try validateSnapshotMerkleProofPosition(proof.position, branch: branch)
        return OpalBase.Transaction.MerkleProof(
            blockHeight: proof.blockHeight,
            position: proof.position,
            branch: branch,
            blockHash: blockHash
        )
    }

    private func validateSnapshotMerkleProofPosition(_ position: UInt32, branch: [Data]) throws {
        guard branch.count < UInt32.bitWidth else {
            throw OpalBase.Address.Book.Error.invalidSnapshotVerificationState
        }
        let maximumPosition = UInt32(1) << branch.count
        guard position < maximumPosition else {
            throw OpalBase.Address.Book.Error.invalidSnapshotVerificationState
        }
    }

    private func hasHexadecimalPrefix(_ value: String) -> Bool {
        value.hasPrefix("0x") || value.hasPrefix("0X")
    }

    private func validateUniqueTokenDeltas(
        in tokenDeltas: [OpalBase.CashTokens.TokenData]
    ) throws -> Set<OpalBase.CashTokens.TokenData> {
        var uniqueTokenDeltas: Set<OpalBase.CashTokens.TokenData> = .init()
        for tokenDelta in tokenDeltas where !uniqueTokenDeltas.insert(tokenDelta).inserted {
            throw OpalBase.Address.Book.Error.invalidSnapshotDuplicateTokenDelta(tokenDelta)
        }
        return uniqueTokenDeltas
    }

    private func validateSnapshotFungibleTokenDeltas(
        _ deltas: [OpalBase.CashTokens.CategoryID: Int64]
    ) throws -> [OpalBase.CashTokens.CategoryID: Int64] {
        let maximumDelta = Int64(OpalBase.CashTokens.TokenData.maximumFungibleAmount)
        for delta in deltas.values where delta < -maximumDelta || delta > maximumDelta {
            throw OpalBase.Address.Book.Error.tokenDeltaOverflow
        }
        return deltas
    }

    private func validateSnapshotLockedBCHDelta(_ delta: Int64) throws -> Int64 {
        let maximumDelta = Int64(OpalBase.Satoshi.maximumSatoshi)
        guard delta >= -maximumDelta, delta <= maximumDelta else {
            throw OpalBase.Address.Book.Error.tokenDeltaOverflow
        }
        return delta
    }

    private func validateScriptHashes(
        in scriptHashes: [String],
        restoredEntryScriptHashes: Set<String>
    ) throws -> [String] {
        guard !scriptHashes.isEmpty else {
            throw OpalBase.Address.Book.Error.invalidSnapshotMissingScriptHashes
        }
        var seenScriptHashes: Set<String> = .init()
        var validatedScriptHashes: [String] = .init()
        validatedScriptHashes.reserveCapacity(scriptHashes.count)
        for scriptHash in scriptHashes {
            let data = try makeSnapshotScriptHashData(from: scriptHash)
            let canonicalScriptHash = data.hexadecimalString
            guard seenScriptHashes.insert(canonicalScriptHash).inserted else {
                throw OpalBase.Address.Book.Error.invalidSnapshotDuplicateScriptHash(canonicalScriptHash)
            }
            guard restoredEntryScriptHashes.contains(canonicalScriptHash) else {
                throw OpalBase.Address.Book.Error.invalidSnapshotTransactionScriptHash(canonicalScriptHash)
            }
            validatedScriptHashes.append(canonicalScriptHash)
        }
        return validatedScriptHashes
    }

    private func makeSnapshotScriptHashData(from scriptHash: String) throws -> Data {
        guard !hasHexadecimalPrefix(scriptHash) else {
            throw OpalBase.Address.Book.Error.invalidSnapshotScriptHash(scriptHash)
        }
        let data = try Data(hexadecimalString: scriptHash)
        guard data.count == OpalBase.Transaction.Hash.expectedByteCount else {
            throw OpalBase.Address.Book.Error.invalidSnapshotScriptHashLength(
                expected: OpalBase.Transaction.Hash.expectedByteCount,
                actual: data.count
            )
        }
        return data
    }

    private func restore(
        entrySnapshots: [Snapshot.Entry],
        usage: OpalBase.Key.DerivationPath.Usage,
        restoredEntryBalances: [UInt32: OpalBase.Satoshi]
    ) async throws {
        if let highestIndex = entrySnapshots.map(\.index).max() {
            let entryCount = Int(highestIndex) + 1
            try await generateEntries(for: usage,
                                      entryCount: entryCount,
                                      isUsed: false,
                                      shouldNotifyNewEntries: false)
        }

        for snapshotEntry in entrySnapshots {
            inventory.updateEntry(at: Int(snapshotEntry.index), usage: usage) { entry in
                entry.isUsed = snapshotEntry.isUsed
                entry.isReserved = false
                entry.cache.balance = restoredEntryBalances[snapshotEntry.index]
                entry.cache.lastUpdated = snapshotEntry.lastUpdated
            }
        }

        let numberOfMissingUnusedEntries = gapLimit - inventory.countUnusedEntries(for: usage)
        if numberOfMissingUnusedEntries > 0 {
            try await generateEntries(for: usage,
                                      entryCount: numberOfMissingUnusedEntries,
                                      isUsed: false,
                                      shouldNotifyNewEntries: false)
        }
    }
}

private typealias RestoredEntryBalances = [
    OpalBase.Key.DerivationPath.Usage: [UInt32: OpalBase.Satoshi]
]
