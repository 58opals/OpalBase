// Network+FulcrumTransactionReader.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumTransactionReader {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeout
        
        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeout = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchDetailedTransaction(forTransactionIdentifier transactionIdentifier: String) async throws -> Transaction.Detailed {
            let identifierData: Data
            do {
                identifierData = try Data(hexadecimalString: transactionIdentifier)
            } catch {
                throw Network.Failure(
                    reason: .decoding,
                    message: "Invalid transaction identifier: \(transactionIdentifier)"
                )
            }
            
            let hash = Transaction.Hash(dataFromRPC: identifierData)
            return try await fetchDetailedTransaction(for: hash)
        }
        
        public func fetchDetailedTransaction(for transactionHash: Transaction.Hash) async throws -> Transaction.Detailed {
            if let cached = await Transaction.Cache.shared.loadTransaction(at: transactionHash) {
                return cached
            }
            
            do {
                let verbose = try await fetchVerboseTransaction(for: transactionHash)
                let rawTransactionData = try Data(hexadecimalString: verbose.hex)
                let (transaction, _) = try Transaction.decode(from: rawTransactionData)
                let blockHash = verbose.blockhash.flatMap { try? Data(hexadecimalString: $0) }
                
                let detailed = Transaction.Detailed(
                    transaction: transaction,
                    blockHash: blockHash,
                    blockTime: verbose.blocktime,
                    confirmations: verbose.confirmations,
                    hash: transactionHash,
                    rawTransactionData: rawTransactionData,
                    size: verbose.size ?? UInt32(rawTransactionData.count),
                    time: verbose.time
                )
                
                await Transaction.Cache.shared.put(detailed, at: transactionHash)
                return detailed
            } catch let failure as Network.Failure {
                throw failure
            } catch {
                do {
                    let rawTransactionData = try await fetchRawTransaction(for: transactionHash)
                    let (transaction, _) = try Transaction.decode(from: rawTransactionData)
                    
                    let detailed = Transaction.Detailed(
                        transaction: transaction,
                        blockHash: nil,
                        blockTime: nil,
                        confirmations: nil,
                        hash: transactionHash,
                        rawTransactionData: rawTransactionData,
                        size: UInt32(rawTransactionData.count),
                        time: nil
                    )
                    
                    await Transaction.Cache.shared.put(detailed, at: transactionHash)
                    return detailed
                } catch let fallbackFailure as Network.Failure {
                    throw fallbackFailure
                } catch {
                    throw FulcrumErrorTranslator.translate(error)
                }
            }
        }
        
        public func fetchRawTransaction(for transactionHash: Transaction.Hash) async throws -> Data {
            if let cached = await Transaction.Cache.shared.loadTransaction(at: transactionHash) {
                return cached.rawTransactionData
            }
            
            let identifier = transactionHash.reverseOrder.hexadecimalString
            
            do {
                let result = try await client.request(
                    method: .blockchain(.transaction(.get(transactionHash: identifier, verbose: false))),
                    responseType: Response.Result.Blockchain.Transaction.Get.self,
                    options: .init(timeout: timeouts.transactionConfirmations)
                )
                
                return try Data(hexadecimalString: result.hex)
            } catch let failure as Network.Failure {
                throw failure
            } catch let error as Data.Error {
                throw Network.Failure(reason: .decoding, message: error.localizedDescription)
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
        
        private func fetchVerboseTransaction(for transactionHash: Transaction.Hash) async throws -> TransactionGetVerbose {
            let identifier = transactionHash.reverseOrder.hexadecimalString
            
            do {
                let result = try await client.request(
                    method: .blockchain(.transaction(.get(transactionHash: identifier, verbose: true))),
                    responseType: Response.Result.Blockchain.Transaction.Get.self,
                    options: .init(timeout: timeouts.transactionConfirmations)
                )
                return .init(hex: result.hex,
                             blockhash: result.blockHash,
                             blocktime: UInt32(result.blocktime),
                             confirmations: UInt32(result.confirmations),
                             size: UInt32(result.size),
                             time: UInt32(result.time))
            } catch let failure as Network.Failure {
                throw failure
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
        
        private struct TransactionGetVerbose: Codable, Sendable {
            let hex: String
            let blockhash: String?
            let blocktime: UInt32?
            let confirmations: UInt32?
            let size: UInt32?
            let time: UInt32?
        }
    }
}
