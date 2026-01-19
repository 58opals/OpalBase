// Network+TransactionMerkleProof.swift

import Foundation

extension Network {
    public struct TransactionMerkleProof: Sendable, Equatable {
        public let blockHeight: UInt
        public let position: UInt
        public let merkle: [String]
        
        public init(blockHeight: UInt, position: UInt, merkle: [String]) {
            self.blockHeight = blockHeight
            self.position = position
            self.merkle = merkle
        }
    }
}
