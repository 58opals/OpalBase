// Transaction+History+Entry.swift

import Foundation

extension Transaction.History {
    public struct Entry: Sendable, Hashable {
        public let transactionHash: Transaction.Hash
        public let height: Int
        public let fee: UInt64?
        
        public init(transactionHash: Transaction.Hash, height: Int, fee: UInt64?) {
            self.transactionHash = transactionHash
            self.height = height
            self.fee = fee
        }
    }
}
