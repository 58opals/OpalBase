// NetworkModel+TransactionHistoryEntryModel.swift

import Foundation

extension NetworkModel {
    public struct TransactionHistoryEntryModel: Sendable, Equatable {
        public let transactionIdentifier: String
        public let blockHeight: Int
        public let fee: UInt64?
        
        public init(transactionIdentifier: String, blockHeight: Int, fee: UInt64?) {
            self.transactionIdentifier = transactionIdentifier
            self.blockHeight = blockHeight
            self.fee = fee
        }
    }
}

extension NetworkModel.TransactionHistoryEntryModel {
    func makeHistoryEntry() throws -> TransactionModel.HistoryModel.EntryModel {
        let hash = try NetworkModel.decodeTransactionHash(from: transactionIdentifier,
                                                     label: "transaction identifier")
        return TransactionModel.HistoryModel.EntryModel(transactionHash: hash,
                                         height: blockHeight,
                                         fee: fee)
    }
}
