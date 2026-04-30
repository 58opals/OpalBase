// OpalBase+Network+FulcrumTransactionProofReader.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network {
    public struct FulcrumTransactionProofReader {
        private let client: any OpalBase.Network.Fulcrum.TransactionProofClient
        private let timeouts: OpalBase.Network.FulcrumRequestTimeout
        
        public init(
            client: OpalBase.Network.Fulcrum.Client,
            timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()
        ) {
            self.init(client: client as any OpalBase.Network.Fulcrum.TransactionProofClient, timeouts: timeouts)
        }

        init(
            client: any OpalBase.Network.Fulcrum.TransactionProofClient,
            timeouts: OpalBase.Network.FulcrumRequestTimeout = .init()
        ) {
            self.client = client
            self.timeouts = timeouts
        }
        
        public func fetchMerkleProof(for transactionHash: OpalBase.Transaction.Hash) async throws -> OpalBase.Network.TransactionMerkleProof {
            let identifier = transactionHash.reverseOrder.hexadecimalString
            
            return try await OpalBase.Network.performWithFailureTranslation {
                let heightResult = try await client.fetchTransactionHeight(
                    transactionHash: identifier,
                    options: .init(timeout: timeouts.transactionMerkleProof)
                )
                guard let blockHeight = heightResult.height else {
                    throw SwiftFulcrum.Client.Error.client(
                        .protocolMismatch("Merkle proof requires a confirmed transaction height.")
                    )
                }
                let result = try await client.fetchTransactionMerkleProof(
                    transactionHash: identifier,
                    blockHeight: blockHeight,
                    options: .init(timeout: timeouts.transactionMerkleProof)
                )
                guard result.blockHeight == blockHeight else {
                    throw SwiftFulcrum.Client.Error.client(
                        .protocolMismatch(
                            "Merkle proof block height mismatch: requested=\(blockHeight), response=\(result.blockHeight)"
                        )
                    )
                }
                
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
                let result = try await client.fetchTransactionIdentifier(
                    blockHeight: blockHeight,
                    transactionPosition: position,
                    shouldIncludeMerkleProof: shouldIncludeMerkleProof,
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
