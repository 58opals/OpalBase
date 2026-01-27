// Network+FulcrumScriptHashReader.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumScriptHashReader: ScriptHashReadable {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeout
        private let transactionReader: FulcrumTransactionReader
        
        public init(
            client: FulcrumClient,
            timeouts: FulcrumRequestTimeout = .init(),
            transactionCache: Transaction.Cache = .init()
        ) {
            self.client = client
            self.timeouts = timeouts
            self.transactionReader = FulcrumTransactionReader(
                client: client,
                timeouts: timeouts,
                cache: transactionCache
            )
        }
        
        public func fetchHistory(
            forScriptHash scriptHashHex: String,
            includeUnconfirmed: Bool
        ) async throws -> [Network.TransactionHistoryEntry] {
            try await Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(
                        .scripthash(
                            .getHistory(
                                scripthash: scriptHashHex,
                                fromHeight: nil,
                                toHeight: nil,
                                includeUnconfirmed: includeUnconfirmed
                            )
                        )
                    ),
                    responseType: Response.Result.Blockchain.ScriptHash.GetHistory.self,
                    options: .init(timeout: timeouts.scriptHashHistory)
                )
                
                return result.transactions.map { transaction in
                    TransactionHistoryEntry(
                        transactionIdentifier: transaction.transactionHash,
                        blockHeight: transaction.height,
                        fee: transaction.fee
                    )
                }
            }
        }
        
        public func fetchUnspent(
            forScriptHash scriptHashHex: String,
            tokenFilter: Network.TokenFilter
        ) async throws -> [Transaction.Output.Unspent] {
            try await Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(
                        .scripthash(
                            .listUnspent(
                                scripthash: scriptHashHex,
                                tokenFilter: tokenFilter
                            )
                        )
                    ),
                    responseType: Response.Result.Blockchain.ScriptHash.ListUnspent.self,
                    options: .init(timeout: timeouts.scriptHashUnspent)
                )
                
                return try await withThrowingTaskGroup(of: Transaction.Output.Unspent.self) { group in
                    for item in result.items {
                        group.addTask { try await makeUnspentOutput(from: item) }
                    }
                    
                    var outputs: [Transaction.Output.Unspent] = .init()
                    outputs.reserveCapacity(result.items.count)
                    
                    for try await output in group {
                        outputs.append(output)
                    }
                    
                    return outputs
                }
            }
        }
        
        private func makeUnspentOutput(
            from item: Response.Result.Blockchain.ScriptHash.ListUnspent.Item
        ) async throws -> Transaction.Output.Unspent {
            guard let index = UInt32(exactly: item.transactionPosition) else {
                throw Network.Failure(reason: .decoding, message: "Transaction position overflow")
            }
            
            let data = try Data(hexadecimalString: item.transactionHash)
            let hash = Transaction.Hash(dataFromRPC: data)
            let rawTransactionData = try await transactionReader.fetchRawTransaction(for: hash)
            let (transaction, _) = try Transaction.decode(from: rawTransactionData)
            let outputIndex = Int(index)
            
            guard transaction.outputs.indices.contains(outputIndex) else {
                throw Network.Failure(
                    reason: .decoding,
                    message: "Missing transaction output at index \(index) for transaction \(item.transactionHash)"
                )
            }
            
            let output = transaction.outputs[outputIndex]
            return Transaction.Output.Unspent(
                output: output,
                previousTransactionHash: hash,
                previousTransactionOutputIndex: index
            )
        }
    }
}
