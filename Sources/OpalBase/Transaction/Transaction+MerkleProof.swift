// Transaction+MerkleProof.swift

import Foundation

extension Transaction {
    public struct MerkleProof {
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
        
        public func computeRoot(for transactionHash: Transaction.Hash) -> Data {
            var current = transactionHash.naturalOrder
            var index = position
            
            for node in branch {
                if index & 1 == 1 {
                    current = HASH256.hash(node + current)
                } else {
                    current = HASH256.hash(current + node)
                }
                index >>= 1
            }
            
            return current
        }
    }
}

extension Transaction.MerkleProof: Sendable {}
extension Transaction.MerkleProof: Hashable {}
extension Transaction.MerkleProof: Codable {}
