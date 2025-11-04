// Network+TransactionHistoryEntry.swift

import Foundation

extension Network {
    public struct TransactionHistoryEntry: Sendable, Equatable {
        public let transactionIdentifier: String
        public let blockHeight: Int
        public let fee: UInt?
        
        public init(transactionIdentifier: String, blockHeight: Int, fee: UInt?) {
            self.transactionIdentifier = transactionIdentifier
            self.blockHeight = blockHeight
            self.fee = fee
        }
    }
}
