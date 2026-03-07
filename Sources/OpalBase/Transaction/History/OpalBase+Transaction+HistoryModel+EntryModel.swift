// OpalBase.Transaction+HistoryModel+EntryModel.swift

import Foundation

extension _OpalBase.Transaction.HistoryModel {
    public struct EntryModel: Sendable, Hashable {
        public let transactionHash: OpalBase.Transaction.HashModel
        public let height: Int
        public let fee: UInt64?
        
        public init(transactionHash: OpalBase.Transaction.HashModel, height: Int, fee: UInt64?) {
            self.transactionHash = transactionHash
            self.height = height
            self.fee = fee
        }
    }
}
