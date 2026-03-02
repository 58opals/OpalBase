// TransactionModel+MerkleProofModel.swift

import Foundation
import OpalCrypto

extension TransactionModel {
    public struct MerkleProofModel {
        public let blockHeight: UInt32
        public let position: UInt32
        public let branch: [Data]
        public let blockHash: Data?
        
        public init(blockHeight: UInt32,
                    position: UInt32,
                    branch: [Data],
                    blockHash: Data? = nil) {
            self.blockHeight = blockHeight
            self.position = position
            self.branch = branch
            self.blockHash = blockHash
        }
        
        public func computeRoot(for transactionHash: TransactionModel.HashModel) -> Data {
            var current = transactionHash.naturalOrder
            var index = position
            
            for node in branch {
                if index & 1 == 1 {
                    current = SecureHash256Model.hash(node + current)
                } else {
                    current = SecureHash256Model.hash(current + node)
                }
                index >>= 1
            }
            
            return current
        }
    }
}

extension TransactionModel.MerkleProofModel: Sendable {}
extension TransactionModel.MerkleProofModel: Hashable {}
extension TransactionModel.MerkleProofModel: Codable {}
