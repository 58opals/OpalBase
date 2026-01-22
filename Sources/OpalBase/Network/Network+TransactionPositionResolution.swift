// Network+TransactionPositionResolution.swift

import Foundation

extension Network {
    public struct TransactionPositionResolution: Sendable, Equatable {
        public let blockHeight: UInt
        public let transactionIdentifier: String
        public let merkle: [String]
        
        public init(blockHeight: UInt, transactionIdentifier: String, merkle: [String]) {
            self.blockHeight = blockHeight
            self.transactionIdentifier = transactionIdentifier
            self.merkle = merkle
        }
    }
}
