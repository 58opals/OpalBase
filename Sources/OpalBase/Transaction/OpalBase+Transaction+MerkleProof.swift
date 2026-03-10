// OpalBase+Transaction+MerkleProof.swift

import Foundation

extension _OpalBase.Transaction {
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
        
        public func computeRoot(for transactionHash: OpalBase.Transaction.Hash) -> Data {
            var current = transactionHash.naturalOrder
            var index = position
            
            for node in branch {
                if index & 1 == 1 {
                    current = OpalCryptoAdapter.hash256(node + current)
                } else {
                    current = OpalCryptoAdapter.hash256(current + node)
                }
                index >>= 1
            }
            
            return current
        }
    }
}

extension _OpalBase.Transaction.MerkleProof: Sendable {}
extension _OpalBase.Transaction.MerkleProof: Hashable {}
extension _OpalBase.Transaction.MerkleProof: Codable {}
