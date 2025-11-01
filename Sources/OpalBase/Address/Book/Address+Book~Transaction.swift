// Address+Book~Transaction.swift

import Foundation

extension Address.Book {
    public func listTransactionHistory() -> [History.Transaction.Record] {
        transactionLog.listRecords()
    }
}

extension Address.Book.History.Transaction {
    public struct ChangeSet: Sendable {
        public var inserted: [Record]
        public var updated: [Record]
        public var removed: [Transaction.Hash]
        
        public init(inserted: [Record] = .init(),
                    updated: [Record] = .init(),
                    removed: [Transaction.Hash] = .init()) {
            self.inserted = inserted
            self.updated = updated
            self.removed = removed
        }
        
        public var isEmpty: Bool { inserted.isEmpty && updated.isEmpty && removed.isEmpty }
    }
}

extension Address.Book.History.Transaction.ChangeSet {
    mutating func applyVerificationUpdates(_ records: [Address.Book.History.Transaction.Record]) {
        guard !records.isEmpty else { return }
        for record in records {
            if let index = inserted.firstIndex(where: { $0.transactionHash == record.transactionHash }) {
                inserted[index] = record
            } else if let index = updated.firstIndex(where: { $0.transactionHash == record.transactionHash }) {
                updated[index] = record
            } else {
                updated.append(record)
            }
        }
    }
}

extension Address.Book {
    func updateTransactionHistory(for scriptHash: String,
                                  entries: [History.Transaction.Entry],
                                  timestamp: Date = .now) -> History.Transaction.ChangeSet {
        transactionLog.updateHistory(for: scriptHash,
                                     entries: entries,
                                     timestamp: timestamp)
    }
    
    func updateTransactionVerification(for transactionHash: Transaction.Hash,
                                       status: History.Transaction.VerificationStatus,
                                       proof: Transaction.MerkleProof?,
                                       verifiedHeight: UInt32?,
                                       timestamp: Date = .now) -> History.Transaction.Record? {
        transactionLog.updateVerification(for: transactionHash,
                                          status: status,
                                          proof: proof,
                                          verifiedHeight: verifiedHeight,
                                          timestamp: timestamp)
    }
    
    func invalidateConfirmations(startingAt height: UInt32,
                                 timestamp: Date = .now) -> [History.Transaction.Record] {
        transactionLog.invalidateConfirmations(startingAt: height,
                                               timestamp: timestamp)
    }
}
