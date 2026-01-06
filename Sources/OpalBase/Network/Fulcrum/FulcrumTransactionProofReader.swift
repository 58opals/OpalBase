// Network+FulcrumTransactionProofReader.swift

import Foundation
import SwiftFulcrum

extension Network {
    public struct FulcrumTransactionProofReader {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeout
        
        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeout = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchMerkleProof(for transactionHash: Transaction.Hash) async throws -> TransactionMerkleProof {
            let identifier = transactionHash.reverseOrder.hexadecimalString
            
            do {
                let result = try await client.request(
                    method: .blockchain(.transaction(.getMerkle(transactionHash: identifier))),
                    responseType: Response.Result.Blockchain.Transaction.GetMerkle.self,
                    options: .init(timeout: timeouts.transactionMerkleProof)
                )
                
                return TransactionMerkleProof(
                    blockHeight: result.blockHeight,
                    position: result.position,
                    merkle: result.merkle
                )
            } catch let failure as Network.Failure {
                throw failure
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
        
        public func fetchTransactionIdentifier(atHeight blockHeight: UInt, position: UInt, includeMerkleProof: Bool) async throws -> TransactionPositionResolution {
            do {
                let result = try await client.request(
                    method: .blockchain(.transaction(.idFromPos(blockHeight: blockHeight,
                                                                transactionPosition: position,
                                                                includeMerkleProof: includeMerkleProof))),
                    responseType: Response.Result.Blockchain.Transaction.IDFromPos.self,
                    options: .init(timeout: timeouts.transactionPositionResolution)
                )
                
                return TransactionPositionResolution(
                    blockHeight: blockHeight,
                    transactionIdentifier: result.transactionHash,
                    merkle: result.merkle
                )
            } catch let failure as Network.Failure {
                throw failure
            } catch {
                throw FulcrumErrorTranslator.translate(error)
            }
        }
    }
}
