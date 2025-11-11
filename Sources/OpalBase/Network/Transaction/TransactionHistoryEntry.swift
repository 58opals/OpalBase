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

extension Network.TransactionHistoryEntry {
    func makeHistoryEntry() throws -> Transaction.History.Entry {
        let identifierData: Data
        do {
            identifierData = try Data(hexadecimalString: transactionIdentifier)
        } catch {
            throw Network.Failure(reason: .decoding,
                                  message: "Cannot decode transaction identifier: \(transactionIdentifier)")
        }
        
        let hash = Transaction.Hash(dataFromRPC: identifierData)
        return Transaction.History.Entry(transactionHash: hash,
                                         height: blockHeight,
                                         fee: fee)
    }
}
