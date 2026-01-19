// Networ+AddressFirstUse.swift

import Foundation

extension Network {
    public struct AddressFirstUse: Sendable, Equatable {
        public let blockHeight: UInt
        public let blockHash: String
        public let transactionIdentifier: String
        
        public init(blockHeight: UInt, blockHash: String, transactionIdentifier: String) {
            self.blockHeight = blockHeight
            self.blockHash = blockHash
            self.transactionIdentifier = transactionIdentifier
        }
    }
}
