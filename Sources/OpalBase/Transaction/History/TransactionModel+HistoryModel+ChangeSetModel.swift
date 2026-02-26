// TransactionModel+HistoryModel+ChangeSetModel.swift

import Foundation

extension TransactionModel.HistoryModel {
    public struct ChangeSetModel: Sendable {
        public var inserted: [RecordModel]
        public var updated: [RecordModel]
        public var removed: [TransactionModel.HashModel]
        
        public init(inserted: [RecordModel] = .init(),
                    updated: [RecordModel] = .init(),
                    removed: [TransactionModel.HashModel] = .init()) {
            self.inserted = inserted
            self.updated = updated
            self.removed = removed
        }
        
        public var isEmpty: Bool { inserted.isEmpty && updated.isEmpty && removed.isEmpty }
    }
}

extension TransactionModel.HistoryModel.ChangeSetModel {
    mutating func merge(_ other: Self) {
        inserted.append(contentsOf: other.inserted)
        updated.append(contentsOf: other.updated)
        removed.append(contentsOf: other.removed)
    }
    
    mutating func applyVerificationUpdates(_ records: [TransactionModel.HistoryModel.RecordModel]) {
        guard !records.isEmpty else { return }
        
        var insertedIndicesByHash: [TransactionModel.HashModel: Int] = .init()
        for (index, record) in inserted.enumerated() {
            insertedIndicesByHash[record.transactionHash] = index
        }
        
        var updatedIndicesByHash: [TransactionModel.HashModel: Int] = .init()
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
