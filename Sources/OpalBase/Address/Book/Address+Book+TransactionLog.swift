// Address+Book+TransactionLog.swift

import Foundation

extension Address.Book {
    struct TransactionLog {
        private var records: [Transaction.Hash: History.Transaction.Record]
        private var scriptHashToTransactions: [String: Set<Transaction.Hash>]
        
        init() {
            self.records = .init()
            self.scriptHashToTransactions = .init()
        }
        
        func listRecords() -> [History.Transaction.Record] {
            Array(records.values)
        }
        
        mutating func updateHistory(for scriptHash: String,
                                    entries: [History.Transaction.Entry],
                                    timestamp: Date) -> History.Transaction.ChangeSet {
            let newTransactions = Set(entries.map { $0.transactionHash })
            let previousTransactions = scriptHashToTransactions[scriptHash] ?? .init()
            
            scriptHashToTransactions[scriptHash] = newTransactions
            
            var inserted: [Transaction.Hash: History.Transaction.Record] = .init()
            var updated: [Transaction.Hash: History.Transaction.Record] = .init()
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
                    let record = History.Transaction.Record.makeRecord(for: entry,
                                                                       scriptHash: scriptHash,
                                                                       timestamp: timestamp)
                    records[entry.transactionHash] = record
                    inserted[entry.transactionHash] = record
                }
            }
            
            let removedTransactions = previousTransactions.subtracting(newTransactions)
            for hash in removedTransactions {
                guard var record = records[hash] else { continue }
                let original = record
                record.scriptHashes.remove(scriptHash)
                record.lastUpdatedAt = timestamp
                if record.scriptHashes.isEmpty {
                    records.removeValue(forKey: hash)
                    removed.insert(hash)
                } else {
                    records[hash] = record
                    if record != original {
                        updated[hash] = record
                    }
                }
            }
            
            return History.Transaction.ChangeSet(inserted: Array(inserted.values),
                                                 updated: Array(updated.values),
                                                 removed: Array(removed))
        }
        
        mutating func updateVerification(for transactionHash: Transaction.Hash,
                                         status: History.Transaction.VerificationStatus,
                                         proof: Transaction.MerkleProof?,
                                         verifiedHeight: UInt32?,
                                         timestamp: Date) -> History.Transaction.Record? {
            guard var record = records[transactionHash] else { return nil }
            let original = record
            record.updateVerification(status: status,
                                      proof: proof,
                                      verifiedHeight: verifiedHeight,
                                      checkedAt: timestamp)
            record.lastUpdatedAt = timestamp
            guard record != original else { return nil }
            records[transactionHash] = record
            return record
        }
        
        mutating func invalidateConfirmations(startingAt height: UInt32,
                                              timestamp: Date) -> [History.Transaction.Record] {
            guard !records.isEmpty else { return [] }
            let threshold = UInt64(height)
            var updated: [History.Transaction.Record] = .init()
            for (hash, record) in records {
                guard let confirmationHeight = record.confirmationHeight,
                      confirmationHeight >= threshold else { continue }
                var mutableRecord = record
                mutableRecord.markAsPendingAfterReorganization(timestamp: timestamp)
                mutableRecord.lastUpdatedAt = timestamp
                records[hash] = mutableRecord
                updated.append(mutableRecord)
            }
            return updated
        }
        
        mutating func reset() {
            records.removeAll()
            scriptHashToTransactions.removeAll()
        }
        
        mutating func store(_ record: History.Transaction.Record) {
            records[record.transactionHash] = record
            for scriptHash in record.scriptHashes {
                scriptHashToTransactions[scriptHash, default: .init()].insert(record.transactionHash)
            }
        }
        
        var isEmpty: Bool {
            records.isEmpty
        }
    }
}

extension Address.Book.TransactionLog: Sendable {}
