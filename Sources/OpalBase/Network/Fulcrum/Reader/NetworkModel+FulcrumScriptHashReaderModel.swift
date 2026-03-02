// NetworkModel+FulcrumScriptHashReaderModel.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    public struct FulcrumScriptHashReaderModel: ScriptHashReadableClient {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeoutModel
        private let transactionReader: FulcrumTransactionReaderModel
        
        public init(
            client: FulcrumClient,
            timeouts: FulcrumRequestTimeoutModel = .init(),
            transactionCache: TransactionModel.Cache = .init()
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
        ) async throws -> [NetworkModel.TransactionHistoryEntryModel] {
            try await NetworkModel.performWithFailureTranslation {
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
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.ScriptHashModel.GetHistoryModel.self,
                    options: .init(timeout: timeouts.scriptHashHistory)
                )
                
                return result.transactions.map { transaction in
                    TransactionHistoryEntryModel(
                        transactionIdentifier: transaction.transactionHash,
                        blockHeight: transaction.height,
                        fee: NetworkModel.resolveFee(transaction.fee)
                    )
                }
            }
        }
        
        public func fetchUnspent(
            forScriptHash scriptHashHex: String,
            tokenFilter: NetworkModel.TokenFilter
        ) async throws -> [TransactionModel.OutputModel.UnspentModel] {
            try await NetworkModel.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(
                        .scripthash(
                            .listUnspent(
                                scripthash: scriptHashHex,
                                tokenFilter: tokenFilter
                            )
                        )
                    ),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.ScriptHashModel.ListUnspentModel.self,
                    options: .init(timeout: timeouts.scriptHashUnspent)
                )
                
                let unspentOutputs = try await result.items.mapConcurrently { item in
                    try await makeUnspentOutput(from: item)
                }
                
                return unspentOutputs.sorted { $0.compareOrder(before: $1) }
            }
        }
        
        private func makeUnspentOutput(
            from item: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.ScriptHashModel.ListUnspentModel.ItemModel
        ) async throws -> TransactionModel.OutputModel.UnspentModel {
            guard let index = UInt32(exactly: item.transactionPosition) else {
                throw NetworkModel.Error(reason: .decoding, message: "TransactionModel position overflow")
            }
            
            let hash = try NetworkModel.decodeTransactionHash(
                from: item.transactionHash,
                label: "script-hash unspent transaction hash"
            )
            let rawTransactionData = try await transactionReader.fetchRawTransaction(for: hash)
            let (transaction, _) = try TransactionModel.decode(from: rawTransactionData)
            let outputIndex = Int(index)
            
            guard transaction.outputs.indices.contains(outputIndex) else {
                throw NetworkModel.Error(
                    reason: .decoding,
                    message: "Missing transaction output at index \(index) for transaction \(item.transactionHash)"
                )
            }
            
            let output = transaction.outputs[outputIndex]
            return TransactionModel.OutputModel.UnspentModel(
                output: output,
                previousTransactionHash: hash,
                previousTransactionOutputIndex: index
            )
        }
    }
}
