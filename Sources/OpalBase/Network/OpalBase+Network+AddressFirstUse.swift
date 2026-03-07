// OpalBase.Network+AddressFirstUse.swift

import Foundation

extension _OpalBase.Network {
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

