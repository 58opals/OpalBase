// BCMR+AuthchainResolver.swift

import Foundation

extension BitcoinCashMetadataRegistries {
    public struct AuthchainResolver: Sendable {
        public let transactionReader: Network.TransactionReadable
        public let addressReader: Network.AddressReadable
        public let scriptHashReader: Network.ScriptHashReadable?
        public let maxDepth: Int
        
        public init(
            transactionReader: Network.TransactionReadable,
            addressReader: Network.AddressReadable,
            scriptHashReader: Network.ScriptHashReadable? = nil,
            maxDepth: Int
        ) {
            self.transactionReader = transactionReader
            self.addressReader = addressReader
            self.scriptHashReader = scriptHashReader
            self.maxDepth = maxDepth
        }
    }
}

extension BitcoinCashMetadataRegistries.AuthchainResolver {
    enum Error: Swift.Error, Sendable {
        case invalidMaximumDepth(Int)
        case maximumDepthExceeded(maxDepth: Int, lastTransactionHash: Transaction.Hash)
        case missingIdentityOutput(Transaction.Hash)
        case scriptHashReaderUnavailable(Transaction.Hash)
        case transactionDecodingFailed(Transaction.Hash, Swift.Error)
        case lockingScriptDecodingFailed(Transaction.Hash, Swift.Error)
    }
    
    public func resolveAuthhead(from authbase: Transaction.Hash) async throws -> Transaction.Hash {
        guard maxDepth >= 0 else {
            throw Error.invalidMaximumDepth(maxDepth)
        }
        
        var current = authbase
        var depth = 0
        let identityOutputIndex: UInt32 = 0
        
        while true {
            let transaction = try await fetchTransaction(for: current)
            guard let identityOutput = transaction.outputs.first else {
                throw Error.missingIdentityOutput(current)
            }
            
            let historyEntries = try await fetchHistoryEntries(
                for: identityOutput.lockingScript,
                transactionHash: current
            )
            
            if let spendingTransactionHash = try await findSpendingTransactionHash(
                in: historyEntries,
                spentTransactionHash: current,
                outputIndex: identityOutputIndex
            ) {
                if depth >= maxDepth {
                    throw Error.maximumDepthExceeded(maxDepth: maxDepth, lastTransactionHash: current)
                }
                current = spendingTransactionHash
                depth += 1
                continue
            }
            
            return current
        }
    }
}

private extension BitcoinCashMetadataRegistries.AuthchainResolver {
    func fetchTransaction(for transactionHash: Transaction.Hash) async throws -> Transaction {
        let rawTransactionData = try await transactionReader.fetchRawTransaction(for: transactionHash)
        do {
            return try Transaction.decode(from: rawTransactionData).transaction
        } catch {
            throw Error.transactionDecodingFailed(transactionHash, error)
        }
    }
    
    func fetchHistoryEntries(
        for lockingScript: Data,
        transactionHash: Transaction.Hash
    ) async throws -> [Network.TransactionHistoryEntry] {
        if let script = try? Script.decode(lockingScript: lockingScript) {
            if script.isDerivableFromAddress {
                let address = try Address(script: script, format: .tokenAware)
                return try await addressReader.fetchHistory(
                    for: address.tokenAwareString,
                    includeUnconfirmed: true
                )
            }
        } else if scriptHashReader == nil {
            throw Error.lockingScriptDecodingFailed(
                transactionHash,
                Script.Error.cannotDecodeScript
            )
        }
        
        guard let scriptHashReader else {
            throw Error.scriptHashReaderUnavailable(transactionHash)
        }
        
        let scriptHash = SHA256.hash(lockingScript).reversedData.hexadecimalString
        return try await scriptHashReader.fetchHistory(
            forScriptHash: scriptHash,
            includeUnconfirmed: true
        )
    }
    
    func findSpendingTransactionHash(
        in historyEntries: [Network.TransactionHistoryEntry],
        spentTransactionHash: Transaction.Hash,
        outputIndex: UInt32
    ) async throws -> Transaction.Hash? {
        for entry in historyEntries {
            let candidateHash = try Network.decodeTransactionHash(
                from: entry.transactionIdentifier,
                label: "transaction identifier"
            )
            let candidateTransaction = try await fetchTransaction(for: candidateHash)
            if candidateTransaction.inputs.contains(where: { input in
                input.previousTransactionHash == spentTransactionHash
                && input.previousTransactionOutputIndex == outputIndex
            }) {
                return candidateHash
            }
        }
        
        return nil
    }
}
