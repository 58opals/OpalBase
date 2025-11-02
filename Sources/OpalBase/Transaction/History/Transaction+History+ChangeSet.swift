// Transaction+History+ChangeSet.swift

import Foundation

extension Transaction.History {
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

extension Transaction.History.ChangeSet {
    mutating func applyVerificationUpdates(_ records: [Transaction.History.Record]) {
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
