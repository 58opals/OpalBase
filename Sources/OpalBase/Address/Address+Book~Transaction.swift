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
}
