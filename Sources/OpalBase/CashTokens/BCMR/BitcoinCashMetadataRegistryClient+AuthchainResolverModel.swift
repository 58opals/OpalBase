// BitcoinCashMetadataRegistryClient+AuthchainResolverModel.swift

import Foundation

extension BitcoinCashMetadataRegistryClient {
    public struct AuthchainResolverModel: Sendable {
        public let transactionReader: OpalBase.Network.TransactionReadableClient
        public let addressReader: OpalBase.Network.AddressReadable
        public let scriptHashReader: OpalBase.Network.ScriptHashReadableClient?
        public let maxDepth: Int
        
        public init(
            transactionReader: OpalBase.Network.TransactionReadableClient,
            addressReader: OpalBase.Network.AddressReadable,
            scriptHashReader: OpalBase.Network.ScriptHashReadableClient? = nil,
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
        case maximumDepthExceeded(maxDepth: Int, lastTransactionHash: OpalBase.Transaction.HashModel)
        case missingIdentityOutput(OpalBase.Transaction.HashModel)
        case scriptHashReaderUnavailable(OpalBase.Transaction.HashModel)
        case transactionDecodingFailed(OpalBase.Transaction.HashModel, Swift.Error)
        case lockingScriptDecodingFailed(OpalBase.Transaction.HashModel, Swift.Error)
    }
    
    public func resolveAuthhead(from authbase: OpalBase.Transaction.HashModel) async throws -> OpalBase.Transaction.HashModel {
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
    func fetchTransaction(for transactionHash: OpalBase.Transaction.HashModel) async throws -> OpalBase.Transaction {
        let rawTransactionData = try await transactionReader.fetchRawTransaction(for: transactionHash)
        do {
            return try OpalBase.Transaction.decode(from: rawTransactionData).transaction
        } catch {
            throw Error.transactionDecodingFailed(transactionHash, error)
        }
    }
    
    func fetchHistoryEntries(
        for lockingScript: Data,
        transactionHash: OpalBase.Transaction.HashModel
    ) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
        if let script = try? OpalBase.Script.decode(lockingScript: lockingScript) {
            if script.isDerivableFromAddress {
                let address = try OpalBase.Address(script: script, format: .tokenAware)
                return try await addressReader.fetchHistory(
                    for: address.tokenAwareString,
                    includeUnconfirmed: true
                )
            }
        } else if scriptHashReader == nil {
            throw Error.lockingScriptDecodingFailed(
                transactionHash,
                OpalBase.Script.Error.cannotDecodeScript
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
        in historyEntries: [OpalBase.Network.TransactionHistoryEntry],
        spentTransactionHash: OpalBase.Transaction.HashModel,
        outputIndex: UInt32
    ) async throws -> OpalBase.Transaction.HashModel? {
        for entry in historyEntries {
            let candidateHash = try OpalBase.Network.decodeTransactionHash(
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

