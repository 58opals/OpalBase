// Address+Book+History.swift

import Foundation

extension Address.Book { public enum History {} }

extension Address.Book.History { public enum Transaction {} }

extension Address.Book.History.Transaction {
    public struct Entry: Sendable, Hashable {
        public let transactionHash: Transaction.Hash
        public let height: Int
        public let fee: UInt?
        
        public init(transactionHash: Transaction.Hash, height: Int, fee: UInt?) {
            self.transactionHash = transactionHash
            self.height = height
            self.fee = fee
        }
    }
    
    public struct Record: Sendable, Hashable {
        public let transactionHash: Transaction.Hash
        public var height: Int
        public var fee: UInt?
        public var scriptHashes: Set<String>
        public let firstSeenAt: Date
        public var lastUpdatedAt: Date
        
        public var isConfirmed: Bool { height > 0 }
        
        public init(transactionHash: Transaction.Hash,
                    height: Int,
                    fee: UInt?,
                    scriptHashes: Set<String>,
                    firstSeenAt: Date,
                    lastUpdatedAt: Date) {
            self.transactionHash = transactionHash
            self.height = height
            self.fee = fee
            self.scriptHashes = scriptHashes
            self.firstSeenAt = firstSeenAt
            self.lastUpdatedAt = lastUpdatedAt
        }
    }
}
