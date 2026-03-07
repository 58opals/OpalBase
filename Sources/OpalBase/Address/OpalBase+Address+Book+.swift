// OpalBase+Address+Book+.swift

import Foundation

extension _OpalBase.Address.Book {
    func listWalletScriptHashes() -> Set<String> {
        Set(inventory.allEntries.map { entry in
            entry.address.makeScriptHash().hexadecimalString
        })
    }
    
    func updateTokenDeltaCache(
        for entries: [OpalBase.Transaction.HistoryModel.Entry],
        transactionReader: OpalBase.Network.TransactionReadableClient,
        walletScriptHashes: Set<String>,
        tokenDeltaCache: inout [OpalBase.Transaction.HashModel: OpalBase.Transaction.HistoryModel.Record.TokenDelta]
    ) async throws {
        let transactionHashes = entries.map(\.transactionHash).deduplicate()
        let missingHashes = transactionHashes.filter { tokenDeltaCache[$0] == nil }
        guard !missingHashes.isEmpty else { return }
        
        let resolved = try await missingHashes.mapConcurrently(
            transformError: { hash, error in
                OpalBase.Address.Book.Error.transactionDetailsRefreshFailed(hash, error)
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
        for transactionHash: OpalBase.Transaction.HashModel,
        transactionReader: OpalBase.Network.TransactionReadableClient,
        walletScriptHashes: Set<String>
    ) async throws -> OpalBase.Transaction.HistoryModel.Record.TokenDelta {
        let rawTransactionData = try await transactionReader.fetchRawTransaction(for: transactionHash)
        let (transaction, _) = try OpalBase.Transaction.decode(from: rawTransactionData)
        return try await makeTokenDelta(from: transaction,
                                        transactionReader: transactionReader,
                                        walletScriptHashes: walletScriptHashes)
    }
    
    func makeTokenDelta(
        from transaction: OpalBase.Transaction,
        transactionReader: OpalBase.Network.TransactionReadableClient,
        walletScriptHashes: Set<String>
    ) async throws -> OpalBase.Transaction.HistoryModel.Record.TokenDelta {
        let previousHashes = transaction.inputs.map(\.previousTransactionHash).deduplicate()
        let previousTransactions = try await previousHashes.mapConcurrently { hash in
            let rawTransactionData = try await transactionReader.fetchRawTransaction(for: hash)
            let (previousTransaction, _) = try OpalBase.Transaction.decode(from: rawTransactionData)
            return (hash, previousTransaction)
        }
        let previousTransactionsByHash = Dictionary(uniqueKeysWithValues: previousTransactions)
        
        var fungibleDeltas: [OpalBase.CashTokens.CategoryIDModel: Int64] = .init()
        var nonFungibleAdditions: Set<OpalBase.CashTokens.TokenData> = .init()
        var nonFungibleRemovals: Set<OpalBase.CashTokens.TokenData> = .init()
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
        
        return OpalBase.Transaction.HistoryModel.Record.TokenDelta(
            fungibleDeltasByCategory: fungibleDeltas,
            nonFungibleTokenAdditions: nonFungibleAdditions,
            nonFungibleTokenRemovals: nonFungibleRemovals,
            bitcoinCashLockedInTokenOutputDelta: lockedBitcoinCashDelta
        )
    }
    
    func makeScriptHashHex(from lockingScript: Data) -> String {
        SHA256Model.hash(lockingScript).reversedData.hexadecimalString
    }
    
    func makeNonFungibleTokenData(from tokenData: OpalBase.CashTokens.TokenData) -> OpalBase.CashTokens.TokenData? {
        guard let nonFungibleToken = tokenData.nft else { return nil }
        return OpalBase.CashTokens.TokenData(category: tokenData.category,
                                    amount: nil,
                                    nft: nonFungibleToken)
    }
    
    func addFungibleDelta(
        from tokenData: OpalBase.CashTokens.TokenData,
        sign: Int64,
        into deltas: inout [OpalBase.CashTokens.CategoryIDModel: Int64]
    ) {
        guard let amount = tokenData.amount else { return }
        let signedAmount = Int64(amount) * sign
        deltas[tokenData.category, default: 0] += signedAmount
    }
}

