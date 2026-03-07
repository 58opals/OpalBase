// AddressModel+BookActor~Persistence.swift

import Foundation

extension AddressModel.BookActor {
    init(from snapshot: SnapshotModel,
         rootExtendedPrivateKey: PrivateKeyModel.ExtendedModel? = nil,
         rootExtendedPublicKey: PublicKeyModel.ExtendedModel? = nil,
         purpose: DerivationPathModel.PurposeModel,
         coinType: DerivationPathModel.CoinTypeModel,
         account: DerivationPathModel.AccountActor,
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

    public func makeSnapshot() -> SnapshotModel {
        let receiving = makeEntrySnapshots(for: .receiving)
        let change = makeEntrySnapshots(for: .change)

        let utxoSnaps = utxoStore.listUTXOs().map {
            SnapshotModel.UTXOModel(value: $0.value,
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
                SnapshotModel.TransactionModel.MerkleProofModel(blockHeight: proof.blockHeight,
                                                 position: proof.position,
                                                 branch: proof.branch.map { $0.hexadecimalString },
                                                 blockHash: proof.blockHash?.hexadecimalString)
            }
            return SnapshotModel.TransactionModel(transactionHash: record.transactionHash.naturalOrder.hexadecimalString,
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
                                        bitcoinCashLockedInTokenOutputDelta: tokenDelta.bitcoinCashLockedInTokenOutputDelta)
        }

        return SnapshotModel(receivingEntries: receiving,
                        changeEntries: change,
                        utxos: utxoSnaps,
                        transactions: transactionSnaps)
    }

    private func makeEntrySnapshots(for usage: DerivationPathModel.UsageModel) -> [SnapshotModel.EntryModel] {
        inventory.listEntries(for: usage).map { entry in
            SnapshotModel.EntryModel(usage: entry.derivationPath.usage,
                           index: entry.derivationPath.index,
                           isUsed: entry.isUsed,
                           isReserved: entry.isReserved,
                           balance: entry.cache.balance?.uint64,
                           lastUpdated: entry.cache.lastUpdated)
        }
    }

    public func refresh(with snapshot: SnapshotModel) async throws {
        try await apply(entrySnapshots: snapshot.receivingEntries, usage: .receiving)
        try await apply(entrySnapshots: snapshot.changeEntries, usage: .change)

        let restoredUTXOs = try snapshot.utxos.map {
            let tokenData = try $0.makeTokenData()
            return TransactionModel.OutputModel.UnspentModel(value: $0.value,
                                              lockingScript: try Data(hexadecimalString: $0.lockingScript),
                                              tokenData: tokenData,
                                              previousTransactionHash: .init(naturalOrder: try Data(hexadecimalString: $0.transactionHash)),
                                              previousTransactionOutputIndex: $0.outputIndex)
        }

        utxoStore.replace(with: Set(restoredUTXOs))
        clearSpendReservationState()
        transactionLog.reset()

        for transaction in snapshot.transactions {
            let hash = TransactionModel.HashModel(naturalOrder: try Data(hexadecimalString: transaction.transactionHash))
            let proof = try transaction.merkleProof.map { proof -> TransactionModel.MerkleProofModel in
                let branch = try proof.branch.map { try Data(hexadecimalString: $0) }
                let blockHash = try proof.blockHash.map { try Data(hexadecimalString: $0) }
                return TransactionModel.MerkleProofModel(blockHeight: proof.blockHeight,
                                               position: proof.position,
                                               branch: branch,
                                               blockHash: blockHash)
            }
            let chainMetadata = TransactionModel.HistoryModel.RecordModel.ChainMetadata(height: transaction.height,
                                                                         fee: transaction.fee,
                                                                         scriptHashes: Set(transaction.scriptHashes),
                                                                         firstSeenAt: transaction.firstSeenAt,
                                                                         lastUpdatedAt: transaction.lastUpdatedAt)
            let confirmationMetadata = TransactionModel.HistoryModel.RecordModel.ConfirmationMetadata(height: transaction.confirmationHeight,
                                                                                       confirmedAt: transaction.confirmedAt)
            let verificationMetadata = TransactionModel.HistoryModel.RecordModel.VerificationMetadata(status: transaction.verificationStatus,
                                                                                       merkleProof: proof,
                                                                                       lastVerifiedHeight: transaction.lastVerifiedHeight,
                                                                                       lastCheckedAt: transaction.lastCheckedAt)
            let tokenDelta = TransactionModel.HistoryModel.RecordModel.TokenDeltaModel(
                fungibleDeltasByCategory: transaction.fungibleTokenDeltasByCategory ?? .init(),
                nonFungibleTokenAdditions: Set(transaction.nonFungibleTokenAdditions ?? .init()),
                nonFungibleTokenRemovals: Set(transaction.nonFungibleTokenRemovals ?? .init()),
                bitcoinCashLockedInTokenOutputDelta: transaction.bitcoinCashLockedInTokenOutputDelta ?? 0
            )
            let record = TransactionModel.HistoryModel.RecordModel(transactionHash: hash,
                                                    status: transaction.status,
                                                    chainMetadata: chainMetadata,
                                                    confirmationMetadata: confirmationMetadata,
                                                    verificationMetadata: verificationMetadata,
                                                    tokenDelta: tokenDelta)
            transactionLog.store(record)
        }
    }

    private func apply(entrySnapshots: [SnapshotModel.EntryModel], usage: DerivationPathModel.UsageModel) async throws {
        guard !entrySnapshots.isEmpty else { return }

        guard let highestIndex = entrySnapshots.map(\.index).max() else { return }

        let highestIndexValue = Int(highestIndex)
        let currentCount = inventory.countEntries(for: usage)
        if currentCount <= highestIndexValue {
            let desiredCount = highestIndexValue + 1
            let numberOfMissingEntries = desiredCount - currentCount
            if numberOfMissingEntries > 0 {
                try await generateEntries(for: usage,
                                          numberOfNewEntries: numberOfMissingEntries,
                                          isUsed: false)
            }
        }

        for snap in entrySnapshots {
            let restoredBalance: SatoshiModel?
            if let balanceValue = snap.balance {
                do {
                    restoredBalance = try SatoshiModel(balanceValue)
                } catch {

                    throw AddressModel.BookActor.Error.invalidSnapshotBalance(value: balanceValue, reason: error)
                }
            } else {
                restoredBalance = nil
            }

            inventory.updateEntry(at: Int(snap.index), usage: usage) { entry in
                entry.isUsed = snap.isUsed
                entry.isReserved = snap.isReserved
                entry.cache.balance = restoredBalance
                entry.cache.lastUpdated = snap.lastUpdated
            }
        }

        let entries = inventory.listEntries(for: usage)
        let unusedEntriesBeyondHighestIndex = entries.filter { entry in
            Int(entry.derivationPath.index) > highestIndexValue && !entry.isUsed
        }.count

        let numberOfMissingUnusedEntries = gapLimit - unusedEntriesBeyondHighestIndex
        if numberOfMissingUnusedEntries > 0 {
            try await generateEntries(for: usage,
                                      numberOfNewEntries: numberOfMissingUnusedEntries,
                                      isUsed: false)
        }
    }
}

