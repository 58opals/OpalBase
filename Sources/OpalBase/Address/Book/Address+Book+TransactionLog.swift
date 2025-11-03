// Address+Book+TransactionLog.swift

import Foundation

extension Address.Book {
    public struct TransactionLog {
        private var records: [Transaction.Hash: Transaction.History.Record]
        
        public init() {
            self.records = .init()
        }
        
        public func listRecords() -> [Transaction.History.Record] {
            Array(records.values)
        }
        
        public mutating func updateHistory(for scriptHash: String,
                                           entries: [Transaction.History.Entry],
                                           timestamp: Date) -> Transaction.History.ChangeSet {
            let newTransactions = Set(entries.map { $0.transactionHash })
            let previousTransactions = listTransactions(for: scriptHash)
            var inserted: [Transaction.Hash: Transaction.History.Record] = .init()
            var updated: [Transaction.Hash: Transaction.History.Record] = .init()
            var removed: Set<Transaction.Hash> = .init()
            
            for entry in entries {
                if var record = records[entry.transactionHash] {
                    let original = record
                    record.resolveUpdate(from: entry, scriptHash: scriptHash, timestamp: timestamp)
                    records[entry.transactionHash] = record
                    if record != original {
                        updated[entry.transactionHash] = record
                    }
                } else {
                    let record = Transaction.History.Record.makeRecord(for: entry,
                                                                       scriptHash: scriptHash,
                                                                       timestamp: timestamp)
                    records[entry.transactionHash] = record
                    inserted[entry.transactionHash] = record
                }
            }
            
            let removedTransactions = previousTransactions.subtracting(newTransactions)
            for transactionHash in removedTransactions {
                guard var record = records[transactionHash] else { continue }
                let original = record
                record.chainMetadata.scriptHashes.remove(scriptHash)
                record.chainMetadata.lastUpdatedAt = timestamp
                if record.chainMetadata.scriptHashes.isEmpty {
                    records.removeValue(forKey: transactionHash)
                    removed.insert(transactionHash)
                } else {
                    records[transactionHash] = record
                    if record != original {
                        updated[transactionHash] = record
                    }
                }
            }
            
            return Transaction.History.ChangeSet(inserted: Array(inserted.values),
                                                 updated: Array(updated.values),
                                                 removed: Array(removed))
        }
        
        public mutating func updateVerification(for transactionHash: Transaction.Hash,
                                                status: Transaction.History.Status.Verification,
                                                proof: Transaction.MerkleProof?,
                                                verifiedHeight: UInt32?,
                                                timestamp: Date) -> Transaction.History.Record? {
            guard var record = records[transactionHash] else { return nil }
            let original = record
            record.updateVerification(status: status,
                                      proof: proof,
                                      verifiedHeight: verifiedHeight,
                                      checkedAt: timestamp)
            record.chainMetadata.lastUpdatedAt = timestamp
            guard record != original else { return nil }
            records[transactionHash] = record
            return record
        }
        
        public mutating func invalidateConfirmations(startingAt height: UInt32,
                                                     timestamp: Date) -> [Transaction.History.Record] {
            guard !records.isEmpty else { return [] }
            let threshold = UInt64(height)
            var updated: [Transaction.History.Record] = .init()
            for (transactionHash, record) in records {
                guard let confirmationHeight = record.confirmationMetadata.height,
                      confirmationHeight >= threshold else { continue }
                var mutableRecord = record
                mutableRecord.markAsPendingAfterReorganization(timestamp: timestamp)
                mutableRecord.chainMetadata.lastUpdatedAt = timestamp
                records[transactionHash] = mutableRecord
                updated.append(mutableRecord)
            }
            return updated
        }
        
        public mutating func reset() {
            records.removeAll()
        }
        
        public mutating func store(_ record: Transaction.History.Record) {
            records[record.transactionHash] = record
        }
        
        public var isEmpty: Bool {
            records.isEmpty
        }
        
        private func listTransactions(for scriptHash: String) -> Set<Transaction.Hash> {
            records.values.reduce(into: Set<Transaction.Hash>()) { transactions, record in
                guard record.chainMetadata.scriptHashes.contains(scriptHash) else { return }
                transactions.insert(record.transactionHash)
            }
        }
    }
}

extension Address.Book.TransactionLog: Sendable {}

extension Address.Book {
    func listTransactionRecords() -> [Transaction.History.Record] {
        transactionLog.listRecords()
    }
    
    func resetTransactionLog() {
        transactionLog.reset()
    }
    
    func storeTransactionRecord(_ record: Transaction.History.Record) {
        transactionLog.store(record)
    }
}
