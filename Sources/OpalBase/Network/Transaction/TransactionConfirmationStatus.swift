// Network+TransactionConfirmationStatus.swift

import Foundation

extension Network {
    public struct TransactionConfirmationStatus: Sendable, Equatable {
        public let transactionHash: Transaction.Hash
        public let transactionHeight: Int?
        public let tipHeight: UInt64
        public let confirmations: UInt?
        
        public init(transactionHash: Transaction.Hash,
                    transactionHeight: Int?,
                    tipHeight: UInt64,
                    confirmations: UInt?) {
            self.transactionHash = transactionHash
            self.transactionHeight = transactionHeight
            self.tipHeight = tipHeight
            self.confirmations = confirmations
        }
    }
}
