// Address+Book~Transaction.swift

import Foundation

extension Address.Book {
    public func listTransactionHistory() -> [History.Transaction.Record] {
        Array(transactionHistories.values)
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
        let newTransactions = Set(entries.map { $0.transactionHash })
        let previousTransactions = scriptHashToTransactions[scriptHash] ?? .init()
        
        scriptHashToTransactions[scriptHash] = newTransactions
        
        var inserted: [Transaction.Hash: History.Transaction.Record] = .init()
        var updated: [Transaction.Hash: History.Transaction.Record] = .init()
        var removed: Set<Transaction.Hash> = .init()
        
        for entry in entries {
            if var record = transactionHistories[entry.transactionHash] {
                let original = record
                record.resolveUpdate(from: entry, scriptHash: scriptHash, timestamp: timestamp)
                transactionHistories[entry.transactionHash] = record
                if record != original {
                    updated[entry.transactionHash] = record
                }
            } else {
                let record = History.Transaction.Record.makeRecord(for: entry,
                                                                   scriptHash: scriptHash,
                                                                   timestamp: timestamp)
                transactionHistories[entry.transactionHash] = record
                inserted[entry.transactionHash] = record
            }
        }
        
        let removedTransactions = previousTransactions.subtracting(newTransactions)
        for hash in removedTransactions {
            guard var record = transactionHistories[hash] else { continue }
            let original = record
            record.scriptHashes.remove(scriptHash)
            record.lastUpdatedAt = timestamp
            if record.scriptHashes.isEmpty {
                transactionHistories.removeValue(forKey: hash)
                removed.insert(hash)
            } else {
                transactionHistories[hash] = record
                if record != original {
                    updated[hash] = record
                }
            }
        }
        
        return History.Transaction.ChangeSet(inserted: Array(inserted.values),
                                             updated: Array(updated.values),
                                             removed: Array(removed))
    }
    
    func updateTransactionVerification(for transactionHash: Transaction.Hash,
                                       status: History.Transaction.VerificationStatus,
                                       proof: Transaction.MerkleProof?,
                                       verifiedHeight: UInt32?,
                                       timestamp: Date = .now) -> History.Transaction.Record? {
        guard var record = transactionHistories[transactionHash] else { return nil }
        let original = record
        record.updateVerification(status: status,
                                  proof: proof,
                                  verifiedHeight: verifiedHeight,
                                  checkedAt: timestamp)
        record.lastUpdatedAt = timestamp
        guard record != original else { return nil }
        transactionHistories[transactionHash] = record
        return record
    }
    
    func invalidateConfirmations(startingAt height: UInt32,
                                 timestamp: Date = .now) -> [History.Transaction.Record] {
        guard !transactionHistories.isEmpty else { return [] }
        let threshold = UInt64(height)
        var updated: [History.Transaction.Record] = .init()
        for (hash, record) in transactionHistories {
            guard let confirmationHeight = record.confirmationHeight,
                  confirmationHeight >= threshold else { continue }
            var mutableRecord = record
            mutableRecord.markAsPendingAfterReorganization(timestamp: timestamp)
            mutableRecord.lastUpdatedAt = timestamp
            transactionHistories[hash] = mutableRecord
            updated.append(mutableRecord)
        }
        return updated
    }
}
