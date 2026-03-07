// OpalBase+Network+TransactionHistoryEntry.swift

import Foundation

extension _OpalBase.Network {
    public struct TransactionHistoryEntry: Sendable, Equatable {
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

extension _OpalBase.Network.TransactionHistoryEntry {
    func makeHistoryEntry() throws -> OpalBase.Transaction.HistoryModel.EntryModel {
        let hash = try OpalBase.Network.decodeTransactionHash(from: transactionIdentifier,
                                                     label: "transaction identifier")
        return OpalBase.Transaction.HistoryModel.EntryModel(transactionHash: hash,
                                         height: blockHeight,
                                         fee: fee)
    }
}
