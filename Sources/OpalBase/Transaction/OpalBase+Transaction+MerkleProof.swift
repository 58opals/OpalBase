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
            self.branch = branch.map { Data($0) }
            self.blockHash = blockHash.map { Data($0) }
        }
        
        public func computeRoot(for transactionHash: OpalBase.Transaction.Hash) -> Data {
            guard Self.canComputeRoot(
                for: transactionHash,
                branch: branch,
                position: position
            ) else {
                return Data()
            }

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

        private static func canComputeRoot(
            for transactionHash: OpalBase.Transaction.Hash,
            branch: [Data],
            position: UInt32
        ) -> Bool {
            guard transactionHash.naturalOrder.count == OpalBase.Transaction.Hash.expectedByteCount,
                  branch.allSatisfy({ $0.count == OpalBase.Transaction.Hash.expectedByteCount }),
                  branch.count < UInt32.bitWidth else {
                return false
            }
            return position < (UInt32(1) << UInt32(branch.count))
        }
    }
}

extension _OpalBase.Transaction.MerkleProof: Sendable {}
extension _OpalBase.Transaction.MerkleProof: Hashable {}
extension _OpalBase.Transaction.MerkleProof: Codable {}
