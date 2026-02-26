// NetworkModel+FulcrumTransactionProofReaderModel.swift

import Foundation
import SwiftFulcrum

extension NetworkModel {
    public struct FulcrumTransactionProofReaderModel {
        private let client: FulcrumClient
        private let timeouts: FulcrumRequestTimeoutModel
        
        public init(client: FulcrumClient, timeouts: FulcrumRequestTimeoutModel = .init()) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchMerkleProof(for transactionHash: TransactionModel.HashModel) async throws -> TransactionMerkleProofModel {
            let identifier = transactionHash.reverseOrder.hexadecimalString
            
            return try await NetworkModel.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.transaction(.getMerkle(transactionHash: identifier))),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.TransactionModel.GetMerkleModel.self,
                    options: .init(timeout: timeouts.transactionMerkleProof)
                )
                
                return TransactionMerkleProofModel(
                    blockHeight: result.blockHeight,
                    position: result.position,
                    merkle: result.merkle
                )
            }
        }
        
        public func fetchTransactionIdentifier(atHeight blockHeight: UInt, position: UInt, shouldIncludeMerkleProof: Bool) async throws -> TransactionPositionResolutionModel {
            try await NetworkModel.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.transaction(.idFromPos(blockHeight: blockHeight,
                                                                transactionPosition: position,
                                                                shouldIncludeMerkleProof: shouldIncludeMerkleProof))),
                    responseType: SwiftFulcrum.FulcrumResponse.ResultModel.BlockchainModel.TransactionModel.IDFromPosModel.self,
                    options: .init(timeout: timeouts.transactionPositionResolution)
                )
                
                return TransactionPositionResolutionModel(
                    blockHeight: blockHeight,
                    transactionIdentifier: result.transactionHash,
                    merkle: result.merkle
                )
            }
        }
    }
}
