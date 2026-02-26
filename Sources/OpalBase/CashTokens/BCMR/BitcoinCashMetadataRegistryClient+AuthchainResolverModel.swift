// BCMR+AuthchainResolverModel.swift

import Foundation

extension BitcoinCashMetadataRegistryClient {
    public struct AuthchainResolverModel: Sendable {
        public let transactionReader: NetworkModel.TransactionReadableClient
        public let addressReader: NetworkModel.AddressReadable
        public let scriptHashReader: NetworkModel.ScriptHashReadableClient?
        public let maxDepth: Int
        
        public init(
            transactionReader: NetworkModel.TransactionReadableClient,
            addressReader: NetworkModel.AddressReadable,
            scriptHashReader: NetworkModel.ScriptHashReadableClient? = nil,
            maxDepth: Int
        ) {
            self.transactionReader = transactionReader
            self.addressReader = addressReader
            self.scriptHashReader = scriptHashReader
            self.maxDepth = maxDepth
        }
    }
}

extension BitcoinCashMetadataRegistryClient.AuthchainResolverModel {
    enum Error: Swift.Error, Sendable {
        case invalidMaximumDepth(Int)
        case maximumDepthExceeded(maxDepth: Int, lastTransactionHash: TransactionModel.HashModel)
        case missingIdentityOutput(TransactionModel.HashModel)
        case scriptHashReaderUnavailable(TransactionModel.HashModel)
        case transactionDecodingFailed(TransactionModel.HashModel, Swift.Error)
        case lockingScriptDecodingFailed(TransactionModel.HashModel, Swift.Error)
    }
    
    public func resolveAuthhead(from authbase: TransactionModel.HashModel) async throws -> TransactionModel.HashModel {
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

private extension BitcoinCashMetadataRegistryClient.AuthchainResolverModel {
    func fetchTransaction(for transactionHash: TransactionModel.HashModel) async throws -> TransactionModel {
        let rawTransactionData = try await transactionReader.fetchRawTransaction(for: transactionHash)
        do {
            return try TransactionModel.decode(from: rawTransactionData).transaction
        } catch {
            throw Error.transactionDecodingFailed(transactionHash, error)
        }
    }
    
    func fetchHistoryEntries(
        for lockingScript: Data,
        transactionHash: TransactionModel.HashModel
    ) async throws -> [NetworkModel.TransactionHistoryEntryModel] {
        if let script = try? ScriptModel.decode(lockingScript: lockingScript) {
            if script.isDerivableFromAddress {
                let address = try AddressModel(script: script, format: .tokenAware)
                return try await addressReader.fetchHistory(
                    for: address.tokenAwareString,
                    includeUnconfirmed: true
                )
            }
        } else if scriptHashReader == nil {
            throw Error.lockingScriptDecodingFailed(
                transactionHash,
                ScriptModel.Error.cannotDecodeScript
            )
        }
        
        guard let scriptHashReader else {
            throw Error.scriptHashReaderUnavailable(transactionHash)
        }
        
        let scriptHash = SHA256Model.hash(lockingScript).reversedData.hexadecimalString
        return try await scriptHashReader.fetchHistory(
            forScriptHash: scriptHash,
            includeUnconfirmed: true
        )
    }
    
    func findSpendingTransactionHash(
        in historyEntries: [NetworkModel.TransactionHistoryEntryModel],
        spentTransactionHash: TransactionModel.HashModel,
        outputIndex: UInt32
    ) async throws -> TransactionModel.HashModel? {
        for entry in historyEntries {
            let candidateHash = try NetworkModel.decodeTransactionHash(
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
