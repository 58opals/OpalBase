// OpalBase.Transaction+HistoryModel+ChangeSetModel.swift

import Foundation

extension _OpalBase.Transaction.HistoryModel {
    public struct ChangeSetModel: Sendable {
        public var inserted: [RecordModel]
        public var updated: [RecordModel]
        public var removed: [OpalBase.Transaction.HashModel]
        
        public init(inserted: [RecordModel] = .init(),
                    updated: [RecordModel] = .init(),
                    removed: [OpalBase.Transaction.HashModel] = .init()) {
            self.inserted = inserted
            self.updated = updated
            self.removed = removed
        }
        
        public var isEmpty: Bool { inserted.isEmpty && updated.isEmpty && removed.isEmpty }
    }
}

extension _OpalBase.Transaction.HistoryModel.ChangeSetModel {
    mutating func merge(_ other: Self) {
        inserted.append(contentsOf: other.inserted)
        updated.append(contentsOf: other.updated)
        removed.append(contentsOf: other.removed)
    }
    
    mutating func applyVerificationUpdates(_ records: [OpalBase.Transaction.HistoryModel.RecordModel]) {
        guard !records.isEmpty else { return }
        
        var insertedIndicesByHash: [OpalBase.Transaction.HashModel: Int] = .init()
        for (index, record) in inserted.enumerated() {
            insertedIndicesByHash[record.transactionHash] = index
        }
        
        var updatedIndicesByHash: [OpalBase.Transaction.HashModel: Int] = .init()
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
