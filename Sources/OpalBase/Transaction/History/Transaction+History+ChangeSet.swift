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
    mutating func merge(_ other: Self) {
        inserted.append(contentsOf: other.inserted)
        updated.append(contentsOf: other.updated)
        removed.append(contentsOf: other.removed)
    }
    
    mutating func applyVerificationUpdates(_ records: [Transaction.History.Record]) {
        guard !records.isEmpty else { return }
        
        var insertedIndicesByHash: [Transaction.Hash: Int] = .init()
        for (index, record) in inserted.enumerated() {
            insertedIndicesByHash[record.transactionHash] = index
        }
        
        var updatedIndicesByHash: [Transaction.Hash: Int] = .init()
        for (index, record) in updated.enumerated() {
            updatedIndicesByHash[record.transactionHash] = index
        }
        
        for record in records {
            if let index = insertedIndicesByHash[record.transactionHash] {
                inserted[index] = record
            } else if let index = updatedIndicesByHash[record.transactionHash] {
                updated[index] = record
            } else {
                updatedIndicesByHash[record.transactionHash] = updated.count
                updated.append(record)
            }
        }
    }
}
