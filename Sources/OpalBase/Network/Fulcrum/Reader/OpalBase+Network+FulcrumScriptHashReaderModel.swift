// OpalBase+Network+FulcrumScriptHashReaderModel.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network {
    public struct FulcrumScriptHashReaderModel: ScriptHashReadableClient {
        private let client: OpalBase.Network.Fulcrum.Client
        private let timeouts: OpalBase.Network.FulcrumRequestTimeoutModel
        private let transactionReader: FulcrumTransactionReaderModel
        
        public init(
            client: OpalBase.Network.Fulcrum.Client,
            timeouts: OpalBase.Network.FulcrumRequestTimeoutModel = .init(),
            transactionCache: OpalBase.Transaction.Cache = .init()
        ) {
            self.client = client
            self.timeouts = timeouts
            self.transactionReader = FulcrumTransactionReaderModel(
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
                let result = try await client.request(
                    method: .blockchain(
                        .scripthash(
                            .getHistory(
                                scripthash: scriptHashHex,
                                fromHeight: nil,
                                toHeight: nil,
                                shouldIncludeUnconfirmed: includeUnconfirmed
                            )
                        )
                    ),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.ScriptHash.GetHistory.self,
                    options: .init(timeout: timeouts.scriptHashHistory)
                )
                
                return result.transactions.map { transaction in
                    OpalBase.Network.TransactionHistoryEntry(
                        transactionIdentifier: transaction.transactionHash,
                        blockHeight: transaction.height,
                        fee: OpalBase.Network.Fulcrum.resolveFee(transaction.fee)
                    )
                }
            }
        }
        
        public func fetchUnspent(
            forScriptHash scriptHashHex: String,
            tokenFilter: OpalBase.Network.TokenFilter
        ) async throws -> [OpalBase.Transaction.OutputModel.Unspent] {
            try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(
                        .scripthash(
                            .listUnspent(
                                scripthash: scriptHashHex,
                                tokenFilter: tokenFilter.fulcrumTokenFilter
                            )
                        )
                    ),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.ScriptHash.ListUnspent.self,
                    options: .init(timeout: timeouts.scriptHashUnspent)
                )
                
                let unspentOutputs = try await result.items.mapConcurrently { item in
                    try await makeUnspentOutput(from: item)
                }
                
                return unspentOutputs.sorted { $0.compareOrder(before: $1) }
            }
        }
        
        private func makeUnspentOutput(
            from item: SwiftFulcrum.RPC.Response.Result.Blockchain.ScriptHash.ListUnspent.Item
        ) async throws -> OpalBase.Transaction.OutputModel.Unspent {
            guard let index = UInt32(exactly: item.transactionPosition) else {
                throw OpalBase.Network.Error(reason: .decoding, message: "OpalBase.Transaction position overflow")
            }
            
            let hash = try OpalBase.Network.decodeTransactionHash(
                from: item.transactionHash,
                label: "script-hash unspent transaction hash"
            )
            let rawTransactionData = try await transactionReader.fetchRawTransaction(for: hash)
            let (transaction, _) = try OpalBase.Transaction.decode(from: rawTransactionData)
            let outputIndex = Int(index)
            
            guard transaction.outputs.indices.contains(outputIndex) else {
                throw OpalBase.Network.Error(
                    reason: .decoding,
                    message: "Missing transaction output at index \(index) for transaction \(item.transactionHash)"
                )
            }
            
            let output = transaction.outputs[outputIndex]
            return OpalBase.Transaction.OutputModel.Unspent(
                output: output,
                previousTransactionHash: hash,
                previousTransactionOutputIndex: index
            )
        }
    }
}
