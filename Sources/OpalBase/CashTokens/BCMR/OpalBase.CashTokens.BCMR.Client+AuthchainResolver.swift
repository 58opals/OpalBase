// OpalBase.CashTokens.BCMR.Client+AuthchainResolver.swift

import Foundation

extension OpalBase.CashTokens.BCMR.Client {
    public struct AuthchainResolver: Sendable {
        public let transactionReader: OpalBase.Network.TransactionReader
        public let addressReader: OpalBase.Network.AddressReader
        public let scriptHashReader: OpalBase.Network.ScriptHashReader?
        public let maxDepth: Int
        
        public init(
            transactionReader: OpalBase.Network.TransactionReader,
            addressReader: OpalBase.Network.AddressReader,
            scriptHashReader: OpalBase.Network.ScriptHashReader? = nil,
            maxDepth: Int
        ) {
            self.transactionReader = transactionReader
            self.addressReader = addressReader
            self.scriptHashReader = scriptHashReader
            self.maxDepth = maxDepth
        }

        init(
            transactionReader: any OpalBase.Network.TransactionReadableClient,
            addressReader: any OpalBase.Network.AddressReadable,
            scriptHashReader: (any OpalBase.Network.ScriptHashReadableClient)? = nil,
            maxDepth: Int
        ) {
            self.init(
                transactionReader: .init(transactionReader),
                addressReader: .init(addressReader),
                scriptHashReader: scriptHashReader.map(OpalBase.Network.ScriptHashReader.init(_:)),
                maxDepth: maxDepth
            )
        }
    }
}

extension OpalBase.CashTokens.BCMR.Client.AuthchainResolver {
    enum Error: Swift.Error, Sendable {
        case invalidMaximumDepth(Int)
        case maximumDepthExceeded(maxDepth: Int, lastTransactionHash: OpalBase.Transaction.Hash)
        case missingIdentityOutput(OpalBase.Transaction.Hash)
        case scriptHashReaderUnavailable(OpalBase.Transaction.Hash)
        case transactionDecodingFailed(OpalBase.Transaction.Hash, Swift.Error)
        case lockingScriptDecodingFailed(OpalBase.Transaction.Hash, Swift.Error)
    }
    
    public func resolveAuthhead(from authbase: OpalBase.Transaction.Hash) async throws -> OpalBase.Transaction.Hash {
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

private extension OpalBase.CashTokens.BCMR.Client.AuthchainResolver {
    func fetchTransaction(for transactionHash: OpalBase.Transaction.Hash) async throws -> OpalBase.Transaction {
        let rawTransactionData = try await transactionReader.fetchRawTransaction(for: transactionHash)
        return try Self.decodeTransaction(rawTransactionData, transactionHash: transactionHash)
    }
}

extension OpalBase.CashTokens.BCMR.Client.AuthchainResolver {
    static func decodeTransaction(
        _ rawTransactionData: Data,
        transactionHash: OpalBase.Transaction.Hash
    ) throws -> OpalBase.Transaction {
        do {
            let decoded = try OpalBase.Transaction.decode(from: rawTransactionData)
            guard decoded.bytesRead == rawTransactionData.count else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Transaction payload has trailing bytes"
                )
            }
            return decoded.transaction
        } catch {
            throw Error.transactionDecodingFailed(transactionHash, error)
        }
    }
}

private extension OpalBase.CashTokens.BCMR.Client.AuthchainResolver {
    func fetchHistoryEntries(
        for lockingScript: Data,
        transactionHash: OpalBase.Transaction.Hash
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
        
        let scriptHash = OpalCryptoAdapter.sha256(lockingScript).reversedData.hexadecimalString
        return try await scriptHashReader.fetchHistory(
            forScriptHash: scriptHash,
            includeUnconfirmed: true
        )
    }
    
    func findSpendingTransactionHash(
        in historyEntries: [OpalBase.Network.TransactionHistoryEntry],
        spentTransactionHash: OpalBase.Transaction.Hash,
        outputIndex: UInt32
    ) async throws -> OpalBase.Transaction.Hash? {
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
