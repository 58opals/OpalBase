// OpalBase+Network+FulcrumScriptHashReader.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    /// Reads script-hash history and UTXOs from a Fulcrum server.
    ///
    /// This reader is public for custom network composition. Wallet flows should
    /// usually start with `OpalBase.Wallet.Fulcrum`.
    public struct ScriptHashReader: OpalBase.Network.ScriptHashReadableClient {
        private let client: OpalBase.Network.Fulcrum.Client
        private let timeouts: OpalBase.Network.FulcrumRequestTimeout
        private let transactionReader: TransactionReader
        
        public init(
            client: OpalBase.Network.Fulcrum.Client,
            timeouts: OpalBase.Network.FulcrumRequestTimeout = .init(),
            transactionCache: OpalBase.Transaction.Cache = .init()
        ) {
            self.client = client
            self.timeouts = timeouts
            self.transactionReader = TransactionReader(
                client: client,
                timeouts: timeouts,
                cache: transactionCache
            )
        }
        
        public func fetchHistory(
            forScriptHash scriptHashHex: String,
            includeUnconfirmed: Bool
        ) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
            try await OpalBase.Network.performWithFailureTranslation {
                let validatedScriptHash = try Self.validateScriptHash(scriptHashHex)
                let result = try await client.request(
                    SwiftFulcrum.API.blockchain.scriptHash.history(
                        scriptHash: validatedScriptHash,
                        shouldIncludeUnconfirmed: includeUnconfirmed
                    ),
                    options: .init(timeout: timeouts.scriptHashHistory)
                )
                
                return try OpalBase.Network.Fulcrum.mapHistoryTransactions(
                    result.transactions,
                    transactionIdentifier: \.transactionHash,
                    blockHeight: \.height,
                    fee: \.fee
                )
            }
        }
        
        public func fetchUnspent(
            forScriptHash scriptHashHex: String,
            tokenFilter: OpalBase.Network.TokenFilter
        ) async throws -> [OpalBase.Transaction.Output.Unspent] {
            try await OpalBase.Network.performWithFailureTranslation {
                let validatedScriptHash = try Self.validateScriptHash(scriptHashHex)
                let result = try await client.request(
                    SwiftFulcrum.API.blockchain.scriptHash.listUnspent(
                        scriptHash: validatedScriptHash,
                        tokenFilter: tokenFilter.fulcrumTokenFilter
                    ),
                    options: .init(timeout: timeouts.scriptHashUnspent)
                )
                
                let unspentOutputs = try await result.items.mapConcurrently { item in
                    try await makeUnspentOutput(from: item, scriptHashHex: validatedScriptHash)
                }
                
                return unspentOutputs.sorted { $0.compareOrder(before: $1) }
            }
        }
        
        private func makeUnspentOutput(
            from item: SwiftFulcrum.Response.Blockchain.ScriptHash.ListUnspent.Item,
            scriptHashHex: String
        ) async throws -> OpalBase.Transaction.Output.Unspent {
            let hash = try OpalBase.Network.decodeTransactionHash(
                from: item.transactionHash,
                label: "script hash unspent transaction hash"
            )
            let rawTransactionData = try await transactionReader.fetchRawTransaction(for: hash)
            return try Self.makeUnspentOutput(
                transactionHash: hash,
                transactionIdentifier: item.transactionHash,
                transactionPosition: item.transactionPosition,
                rawTransactionData: rawTransactionData,
                scriptHashHex: scriptHashHex
            )
        }

        static func makeUnspentOutput(
            transactionHash: OpalBase.Transaction.Hash,
            transactionIdentifier: String,
            transactionPosition: UInt,
            rawTransactionData: Data,
            scriptHashHex: String
        ) throws -> OpalBase.Transaction.Output.Unspent {
            guard let index = UInt32(exactly: transactionPosition) else {
                throw OpalBase.Network.Error(reason: .decoding, message: "OpalBase.Transaction position overflow")
            }
            
            let (transaction, bytesRead) = try OpalBase.Transaction.decode(from: rawTransactionData)
            guard bytesRead == rawTransactionData.count else {
                throw OpalBase.Network.Error(reason: .decoding, message: "Transaction payload has trailing bytes")
            }
            let outputIndex = Int(index)
            
            guard transaction.outputs.indices.contains(outputIndex) else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Missing transaction output at index \(index) for transaction \(transactionIdentifier)"
                )
            }
            
            let output = transaction.outputs[outputIndex]
            let outputScriptHash = OpalCryptoAdapter.sha256(output.lockingScript).reversedData.hexadecimalString
            guard outputScriptHash.caseInsensitiveCompare(scriptHashHex) == .orderedSame else {
                throw OpalBase.Network.Error(
                    reason: .protocolViolation,
                    message: "Unspent transaction output script hash mismatch",
                    metadata: [
                        "expected": scriptHashHex,
                        "actual": outputScriptHash,
                        "transaction": transactionIdentifier,
                        "outputIndex": index.description
                    ]
                )
            }
            
            return OpalBase.Transaction.Output.Unspent(
                output: output,
                previousTransactionHash: transactionHash,
                previousTransactionOutputIndex: index
            )
        }
        
        static func validateScriptHash(_ scriptHash: String) throws -> String {
            try OpalBase.Network.Fulcrum.AddressReader.validateScriptHash(scriptHash)
        }
    }
}
