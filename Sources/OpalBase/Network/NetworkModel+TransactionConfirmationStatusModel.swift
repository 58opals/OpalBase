// NetworkModel+TransactionConfirmationStatusModel.swift

import Foundation

extension NetworkModel {
    public struct TransactionConfirmationStatusModel: Sendable, Equatable {
        public let transactionHash: TransactionModel.HashModel
        public let transactionHeight: Int?
        public let tipHeight: UInt64
        public let confirmations: UInt?
        
        public init(transactionHash: TransactionModel.HashModel,
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
