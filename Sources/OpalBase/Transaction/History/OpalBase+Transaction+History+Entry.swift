// OpalBase+Transaction+History+Entry.swift

import Foundation

extension _OpalBase.Transaction.History {
    public struct Entry: Sendable, Hashable {
        public let transactionHash: OpalBase.Transaction.Hash
        public let height: Int
        public let fee: UInt64?
        
        public init(transactionHash: OpalBase.Transaction.Hash, height: Int, fee: UInt64?) {
            self.transactionHash = transactionHash
            self.height = height
            self.fee = fee
        }
    }
}
