// OpalBase+Network+FulcrumTransactionProofReader.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network {
    public struct FulcrumTransactionProofReader {
        private let client: OpalBase.Network.Fulcrum.Client
        private let timeouts: OpalBase.Network.FulcrumRequestTimeout
        
        public init(
            client: OpalBase.Network.Fulcrum.Client,
            timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()
        ) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchMerkleProof(for transactionHash: OpalBase.Transaction.Hash) async throws -> OpalBase.Network.TransactionMerkleProof {
            let identifier = transactionHash.reverseOrder.hexadecimalString
            
            return try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.transaction(.getMerkle(transactionHash: identifier))),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.GetMerkle.self,
                    options: .init(timeout: timeouts.transactionMerkleProof)
                )
                
                return OpalBase.Network.TransactionMerkleProof(
                    blockHeight: result.blockHeight,
                    position: result.position,
                    merkle: result.merkle
                )
            }
        }
        
        public func fetchTransactionIdentifier(
            atHeight blockHeight: UInt,
            position: UInt,
            shouldIncludeMerkleProof: Bool
        ) async throws -> OpalBase.Network.TransactionPositionResolution {
            try await OpalBase.Network.performWithFailureTranslation {
                let result = try await client.request(
                    method: .blockchain(.transaction(.idFromPos(blockHeight: blockHeight,
                                                                transactionPosition: position,
                                                                shouldIncludeMerkleProof: shouldIncludeMerkleProof))),
                    responseType: SwiftFulcrum.RPC.Response.Result.Blockchain.Transaction.IDFromPos.self,
                    options: .init(timeout: timeouts.transactionPositionResolution)
                )
                
                return OpalBase.Network.TransactionPositionResolution(
                    blockHeight: blockHeight,
                    transactionIdentifier: result.transactionHash,
                    merkle: result.merkle
                )
            }
        }
    }
}
