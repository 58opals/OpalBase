// OpalBase+Address+Book+TokenDelta.swift

import Foundation

extension _OpalBase.Address.Book {
    func listWalletScriptHashes() -> Set<String> {
        Set(inventory.allEntries.map { entry in
            entry.address.makeScriptHash().hexadecimalString
        })
    }
    
    func updateTokenDeltaCache(
        for entries: [OpalBase.Transaction.History.Entry],
        transactionReader: OpalBase.Network.TransactionReader,
        walletScriptHashes: Set<String>,
        tokenDeltaCache: inout [OpalBase.Transaction.Hash: OpalBase.Transaction.History.Record.TokenDelta]
    ) async throws {
        let transactionHashes = entries.map(\.transactionHash).deduplicate()
        let missingHashes = transactionHashes.filter { tokenDeltaCache[$0] == nil }
        guard !missingHashes.isEmpty else { return }
        
        let resolvedTokenDeltas = try await missingHashes.mapConcurrently(
            transformError: { hash, error in
                OpalBase.Address.Book.Error.transactionDetailsRefreshFailed(hash, error)
            }
        ) { hash in
            let tokenDelta = try await self.makeTokenDelta(for: hash,
                                                           transactionReader: transactionReader,
                                                           walletScriptHashes: walletScriptHashes)
            return (hash, tokenDelta)
        }
        
        for (hash, tokenDelta) in resolvedTokenDeltas {
            tokenDeltaCache[hash] = tokenDelta
        }
    }
    
    func makeTokenDelta(
        for transactionHash: OpalBase.Transaction.Hash,
        transactionReader: OpalBase.Network.TransactionReader,
        walletScriptHashes: Set<String>
    ) async throws -> OpalBase.Transaction.History.Record.TokenDelta {
        let transaction = try await fetchCompleteTransaction(
            for: transactionHash,
            transactionReader: transactionReader
        )
        return try await makeTokenDelta(from: transaction,
                                        transactionReader: transactionReader,
                                        walletScriptHashes: walletScriptHashes)
    }
    
    func makeTokenDelta(
        from transaction: OpalBase.Transaction,
        transactionReader: OpalBase.Network.TransactionReader,
        walletScriptHashes: Set<String>
    ) async throws -> OpalBase.Transaction.History.Record.TokenDelta {
        let spendingInputs = transaction.inputs.filter { !$0.isCoinbase }
        let previousTransactionHashes = spendingInputs.map(\.previousTransactionHash).deduplicate()
        let previousTransactions = try await previousTransactionHashes.mapConcurrently { hash in
            let previousTransaction = try await self.fetchCompleteTransaction(
                for: hash,
                transactionReader: transactionReader
            )
            return (hash, previousTransaction)
        }
        let previousTransactionsByHash = Dictionary(uniqueKeysWithValues: previousTransactions)
        
        var fungibleDeltas: [OpalBase.CashTokens.CategoryID: Int64] = .init()
        var nonFungibleAdditions: [OpalBase.CashTokens.TokenData] = .init()
        var nonFungibleRemovals: [OpalBase.CashTokens.TokenData] = .init()
        var lockedBCHDelta: Int64 = 0
        
        for output in transaction.outputs {
            let scriptHash = makeScriptHashHex(from: output.lockingScript)
            guard walletScriptHashes.contains(scriptHash) else { continue }
            guard let tokenData = output.tokenData else { continue }
            try addFungibleDelta(from: tokenData, sign: 1, into: &fungibleDeltas)
            if let nonFungibleTokenData = makeNonFungibleTokenData(from: tokenData) {
                nonFungibleAdditions.append(nonFungibleTokenData)
            }
            try addLockedBCHDelta(output.value, sign: 1, into: &lockedBCHDelta)
        }
        
        for input in spendingInputs {
            guard let previousTransaction = previousTransactionsByHash[input.previousTransactionHash] else {
                throw OpalBase.Transaction.Error.transactionNotFound
            }
            let outputIndex = Int(input.previousTransactionOutputIndex)
            guard previousTransaction.outputs.indices.contains(outputIndex) else {
                throw Data.Error.indexOutOfRange
            }
            let previousOutput = previousTransaction.outputs[outputIndex]
            let scriptHash = makeScriptHashHex(from: previousOutput.lockingScript)
            guard walletScriptHashes.contains(scriptHash) else { continue }
            guard let tokenData = previousOutput.tokenData else { continue }
            try addFungibleDelta(from: tokenData, sign: -1, into: &fungibleDeltas)
            if let nonFungibleTokenData = makeNonFungibleTokenData(from: tokenData) {
                nonFungibleRemovals.append(nonFungibleTokenData)
            }
            try addLockedBCHDelta(previousOutput.value, sign: -1, into: &lockedBCHDelta)
        }

        netNonFungibleTokenDeltas(
            additions: &nonFungibleAdditions,
            removals: &nonFungibleRemovals
        )
        
        return OpalBase.Transaction.History.Record.TokenDelta(
            fungibleDeltasByCategory: fungibleDeltas,
            nonFungibleTokenAdditions: nonFungibleAdditions,
            nonFungibleTokenRemovals: nonFungibleRemovals,
            bchLockedInTokenOutputDelta: lockedBCHDelta
        )
    }
    
    func makeScriptHashHex(from lockingScript: Data) -> String {
        OpalCryptoAdapter.sha256(lockingScript).reversedData.hexadecimalString
    }

    func fetchCompleteTransaction(
        for transactionHash: OpalBase.Transaction.Hash,
        transactionReader: OpalBase.Network.TransactionReader
    ) async throws -> OpalBase.Transaction {
        let rawTransactionData = try await transactionReader.fetchRawTransaction(for: transactionHash)
        try Self.validateTransactionPayloadHash(rawTransactionData, expected: transactionHash)
        return try Self.decodeCompleteTransaction(from: rawTransactionData)
    }

    nonisolated static func decodeCompleteTransaction(from rawTransactionData: Data) throws -> OpalBase.Transaction {
        let (transaction, bytesRead) = try OpalBase.Transaction.decode(from: rawTransactionData)
        guard bytesRead == rawTransactionData.count else {
            throw OpalBase.Network.Error(
                reason: .decoding,
                message: "Transaction payload has trailing bytes"
            )
        }
        return transaction
    }

    nonisolated static func validateTransactionPayloadHash(
        _ rawTransactionData: Data,
        expected transactionHash: OpalBase.Transaction.Hash
    ) throws {
        let actualHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(rawTransactionData)
        )
        guard actualHash == transactionHash else {
            throw OpalBase.Network.Error(
                reason: .protocolViolation,
                message: "Transaction payload hash mismatch",
                metadata: [
                    "expected": transactionHash.reverseOrder.hexadecimalString,
                    "actual": actualHash.reverseOrder.hexadecimalString
                ]
            )
        }
    }

    func netNonFungibleTokenDeltas(
        additions: inout [OpalBase.CashTokens.TokenData],
        removals: inout [OpalBase.CashTokens.TokenData]
    ) {
        let additionCounts: [OpalBase.CashTokens.TokenData: Int] = additions.reduce(
            into: [:]
        ) { counts, tokenData in
            counts[tokenData, default: 0] += 1
        }
        let removalCounts: [OpalBase.CashTokens.TokenData: Int] = removals.reduce(
            into: [:]
        ) { counts, tokenData in
            counts[tokenData, default: 0] += 1
        }
        let cancellationCounts: [OpalBase.CashTokens.TokenData: Int] = additionCounts.reduce(
            into: [:]
        ) { counts, addition in
            guard let removalCount = removalCounts[addition.key] else { return }
            counts[addition.key] = min(addition.value, removalCount)
        }

        var remainingAdditionCancellations = cancellationCounts
        additions.removeAll { tokenData in
            guard remainingAdditionCancellations[tokenData, default: 0] > 0 else { return false }
            remainingAdditionCancellations[tokenData, default: 0] -= 1
            return true
        }

        var remainingRemovalCancellations = cancellationCounts
        removals.removeAll { tokenData in
            guard remainingRemovalCancellations[tokenData, default: 0] > 0 else { return false }
            remainingRemovalCancellations[tokenData, default: 0] -= 1
            return true
        }
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
        into deltas: inout [OpalBase.CashTokens.CategoryID: Int64]
    ) throws {
        guard let amount = tokenData.amount else { return }
        guard let magnitude = Int64(exactly: amount) else {
            throw OpalBase.Address.Book.Error.tokenDeltaOverflow
        }
        let signedAmount = magnitude * sign
        let current = deltas[tokenData.category, default: 0]
        deltas[tokenData.category] = try current.addOrThrow(
            signedAmount,
            overflowError: OpalBase.Address.Book.Error.tokenDeltaOverflow
        )
    }

    func addLockedBCHDelta(
        _ value: UInt64,
        sign: Int64,
        into delta: inout Int64
    ) throws {
        guard let magnitude = Int64(exactly: value) else {
            throw OpalBase.Address.Book.Error.tokenDeltaOverflow
        }
        let signedValue = magnitude * sign
        delta = try delta.addOrThrow(
            signedValue,
            overflowError: OpalBase.Address.Book.Error.tokenDeltaOverflow
        )
    }
}
