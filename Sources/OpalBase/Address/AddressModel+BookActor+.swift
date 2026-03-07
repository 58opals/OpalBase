// AddressModel+BookActor+.swift

import Foundation

extension AddressModel.BookActor {
    func listWalletScriptHashes() -> Set<String> {
        Set(inventory.allEntries.map { entry in
            entry.address.makeScriptHash().hexadecimalString
        })
    }
    
    func updateTokenDeltaCache(
        for entries: [TransactionModel.HistoryModel.EntryModel],
        transactionReader: NetworkModel.TransactionReadableClient,
        walletScriptHashes: Set<String>,
        tokenDeltaCache: inout [TransactionModel.HashModel: TransactionModel.HistoryModel.RecordModel.TokenDeltaModel]
    ) async throws {
        let transactionHashes = entries.map(\.transactionHash).deduplicate()
        let missingHashes = transactionHashes.filter { tokenDeltaCache[$0] == nil }
        guard !missingHashes.isEmpty else { return }
        
        let resolved = try await missingHashes.mapConcurrently(
            transformError: { hash, error in
                AddressModel.BookActor.Error.transactionDetailsRefreshFailed(hash, error)
            }
        ) { hash in
            let tokenDelta = try await self.makeTokenDelta(for: hash,
                                                           transactionReader: transactionReader,
                                                           walletScriptHashes: walletScriptHashes)
            return (hash, tokenDelta)
        }
        
        for (hash, tokenDelta) in resolved {
            tokenDeltaCache[hash] = tokenDelta
        }
    }
    
    func makeTokenDelta(
        for transactionHash: TransactionModel.HashModel,
        transactionReader: NetworkModel.TransactionReadableClient,
        walletScriptHashes: Set<String>
    ) async throws -> TransactionModel.HistoryModel.RecordModel.TokenDeltaModel {
        let rawTransactionData = try await transactionReader.fetchRawTransaction(for: transactionHash)
        let (transaction, _) = try TransactionModel.decode(from: rawTransactionData)
        return try await makeTokenDelta(from: transaction,
                                        transactionReader: transactionReader,
                                        walletScriptHashes: walletScriptHashes)
    }
    
    func makeTokenDelta(
        from transaction: TransactionModel,
        transactionReader: NetworkModel.TransactionReadableClient,
        walletScriptHashes: Set<String>
    ) async throws -> TransactionModel.HistoryModel.RecordModel.TokenDeltaModel {
        let previousHashes = transaction.inputs.map(\.previousTransactionHash).deduplicate()
        let previousTransactions = try await previousHashes.mapConcurrently { hash in
            let rawTransactionData = try await transactionReader.fetchRawTransaction(for: hash)
            let (previousTransaction, _) = try TransactionModel.decode(from: rawTransactionData)
            return (hash, previousTransaction)
        }
        let previousTransactionsByHash = Dictionary(uniqueKeysWithValues: previousTransactions)
        
        var fungibleDeltas: [CashTokensModel.CategoryIDModel: Int64] = .init()
        var nonFungibleAdditions: Set<CashTokensModel.TokenData> = .init()
        var nonFungibleRemovals: Set<CashTokensModel.TokenData> = .init()
        var lockedBitcoinCashDelta: Int64 = 0
        
        for output in transaction.outputs {
            let scriptHash = makeScriptHashHex(from: output.lockingScript)
            guard walletScriptHashes.contains(scriptHash) else { continue }
            guard let tokenData = output.tokenData else { continue }
            addFungibleDelta(from: tokenData, sign: 1, into: &fungibleDeltas)
            if let nonFungibleTokenData = makeNonFungibleTokenData(from: tokenData) {
                nonFungibleAdditions.insert(nonFungibleTokenData)
            }
            lockedBitcoinCashDelta += Int64(output.value)
        }
        
        for input in transaction.inputs {
            guard let previousTransaction = previousTransactionsByHash[input.previousTransactionHash] else { continue }
            let outputIndex = Int(input.previousTransactionOutputIndex)
            guard previousTransaction.outputs.indices.contains(outputIndex) else { continue }
            let previousOutput = previousTransaction.outputs[outputIndex]
            let scriptHash = makeScriptHashHex(from: previousOutput.lockingScript)
            guard walletScriptHashes.contains(scriptHash) else { continue }
            guard let tokenData = previousOutput.tokenData else { continue }
            addFungibleDelta(from: tokenData, sign: -1, into: &fungibleDeltas)
            if let nonFungibleTokenData = makeNonFungibleTokenData(from: tokenData) {
                nonFungibleRemovals.insert(nonFungibleTokenData)
            }
            lockedBitcoinCashDelta -= Int64(previousOutput.value)
        }
        
        return TransactionModel.HistoryModel.RecordModel.TokenDeltaModel(
            fungibleDeltasByCategory: fungibleDeltas,
            nonFungibleTokenAdditions: nonFungibleAdditions,
            nonFungibleTokenRemovals: nonFungibleRemovals,
            bitcoinCashLockedInTokenOutputDelta: lockedBitcoinCashDelta
        )
    }
    
    func makeScriptHashHex(from lockingScript: Data) -> String {
        SHA256Model.hash(lockingScript).reversedData.hexadecimalString
    }
    
    func makeNonFungibleTokenData(from tokenData: CashTokensModel.TokenData) -> CashTokensModel.TokenData? {
        guard let nonFungibleToken = tokenData.nft else { return nil }
        return CashTokensModel.TokenData(category: tokenData.category,
                                    amount: nil,
                                    nft: nonFungibleToken)
    }
    
    func addFungibleDelta(
        from tokenData: CashTokensModel.TokenData,
        sign: Int64,
        into deltas: inout [CashTokensModel.CategoryIDModel: Int64]
    ) {
        guard let amount = tokenData.amount else { return }
        let signedAmount = Int64(amount) * sign
        deltas[tokenData.category, default: 0] += signedAmount
    }
}

