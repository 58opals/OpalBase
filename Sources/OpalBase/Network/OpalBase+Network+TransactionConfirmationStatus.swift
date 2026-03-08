// OpalBase+Network+TransactionConfirmationStatus.swift

import Foundation

extension _OpalBase.Network {
    public struct TransactionConfirmationStatus: Sendable, Equatable {
        public let transactionHash: OpalBase.Transaction.Hash
        public let transactionHeight: Int?
        public let tipHeight: UInt64
        public let confirmations: UInt?
        
        public init(transactionHash: OpalBase.Transaction.Hash,
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
