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
            
            return try await Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.transaction(.getMerkle(transactionHash: identifier))),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.TransactionModel.GetMerkleModel.self,
                    options: .init(timeout: timeouts.transactionMerkleProof)
                )
                
                return TransactionMerkleProof(
                    blockHeight: result.blockHeight,
                    position: result.position,
                    merkle: result.merkle
                )
            }
        }
        
        public func fetchTransactionIdentifier(atHeight blockHeight: UInt, position: UInt, shouldIncludeMerkleProof: Bool) async throws -> TransactionPositionResolution {
            try await Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.transaction(.idFromPos(blockHeight: blockHeight,
                                                                transactionPosition: position,
                                                                shouldIncludeMerkleProof: shouldIncludeMerkleProof))),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.TransactionModel.IDFromPosModel.self,
                    options: .init(timeout: timeouts.transactionPositionResolution)
                )
                
                return TransactionPositionResolution(
                    blockHeight: blockHeight,
                    transactionIdentifier: result.transactionHash,
                    merkle: result.merkle
                )
            }
        }
    }
}
