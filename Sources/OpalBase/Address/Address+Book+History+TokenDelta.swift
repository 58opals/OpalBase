// Address+Book+History+TokenDelta.swift

import Foundation

extension Address.Book {
    func listWalletScriptHashes() -> Set<String> {
        Set(inventory.allEntries.map { entry in
            entry.address.makeScriptHash().hexadecimalString
        })
    }
    
    func updateTokenDeltaCache(
        for entries: [Transaction.History.Entry],
        transactionReader: Network.TransactionReadable,
        walletScriptHashes: Set<String>,
        tokenDeltaCache: inout [Transaction.Hash: Transaction.History.Record.TokenDelta]
    ) async throws {
        let transactionHashes = entries.map(\.transactionHash).deduplicate()
        let missingHashes = transactionHashes.filter { tokenDeltaCache[$0] == nil }
        guard !missingHashes.isEmpty else { return }
        
        let resolved = try await missingHashes.mapConcurrently(
            transformError: { hash, error in
                Address.Book.Error.transactionDetailsRefreshFailed(hash, error)
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
        for transactionHash: Transaction.Hash,
        transactionReader: Network.TransactionReadable,
        walletScriptHashes: Set<String>
    ) async throws -> Transaction.History.Record.TokenDelta {
        let rawTransactionData = try await transactionReader.fetchRawTransaction(for: transactionHash)
        let (transaction, _) = try Transaction.decode(from: rawTransactionData)
        return try await makeTokenDelta(from: transaction,
                                        transactionReader: transactionReader,
                                        walletScriptHashes: walletScriptHashes)
    }
    
    func makeTokenDelta(
        from transaction: Transaction,
        transactionReader: Network.TransactionReadable,
        walletScriptHashes: Set<String>
    ) async throws -> Transaction.History.Record.TokenDelta {
        let previousHashes = transaction.inputs.map(\.previousTransactionHash).deduplicate()
        let previousTransactions = try await previousHashes.mapConcurrently { hash in
            let rawTransactionData = try await transactionReader.fetchRawTransaction(for: hash)
            let (previousTransaction, _) = try Transaction.decode(from: rawTransactionData)
            return (hash, previousTransaction)
        }
        let previousTransactionsByHash = Dictionary(uniqueKeysWithValues: previousTransactions)
        
        var fungibleDeltas: [CashTokens.CategoryID: Int64] = .init()
        var nonFungibleAdditions: Set<CashTokens.TokenData> = .init()
        var nonFungibleRemovals: Set<CashTokens.TokenData> = .init()
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
        
        return Transaction.History.Record.TokenDelta(
            fungibleDeltasByCategory: fungibleDeltas,
            nonFungibleTokenAdditions: nonFungibleAdditions,
            nonFungibleTokenRemovals: nonFungibleRemovals,
            bitcoinCashLockedInTokenOutputDelta: lockedBitcoinCashDelta
        )
    }
    
    func makeScriptHashHex(from lockingScript: Data) -> String {
        SHA256.hash(lockingScript).reversedData.hexadecimalString
    }
    
    func makeNonFungibleTokenData(from tokenData: CashTokens.TokenData) -> CashTokens.TokenData? {
        guard let nonFungibleToken = tokenData.nft else { return nil }
        return CashTokens.TokenData(category: tokenData.category,
                                    amount: nil,
                                    nft: nonFungibleToken)
    }
    
    func addFungibleDelta(
        from tokenData: CashTokens.TokenData,
        sign: Int64,
        into deltas: inout [CashTokens.CategoryID: Int64]
    ) {
        guard let amount = tokenData.amount else { return }
        let signedAmount = Int64(amount) * sign
        deltas[tokenData.category, default: 0] += signedAmount
    }
}
