// TransactionModel+HistoryModel+EntryModel.swift

import Foundation

extension TransactionModel.HistoryModel {
    public struct EntryModel: Sendable, Hashable {
        public let transactionHash: TransactionModel.HashModel
        public let height: Int
        public let fee: UInt64?
        
        public init(transactionHash: TransactionModel.HashModel, height: Int, fee: UInt64?) {
            self.transactionHash = transactionHash
            self.height = height
            self.fee = fee
        }
    }
}
