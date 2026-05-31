// OpalBase+Address+Book+TransactionLog.swift

import Foundation

extension _OpalBase.Address.Book {
    struct TransactionLog {
        private var records: [OpalBase.Transaction.Hash: OpalBase.Transaction.History.Record]
        private var transactionHashesByScriptHash: [String: Set<OpalBase.Transaction.Hash>]
        
        init() {
            self.records = .init()
            self.transactionHashesByScriptHash = .init()
        }
        
        func listRecords() -> [OpalBase.Transaction.History.Record] {
            Array(records.values)
        }
        
        func loadRecord(for transactionHash: OpalBase.Transaction.Hash) -> OpalBase.Transaction.History.Record? {
            records[transactionHash]
        }
        
        mutating func replaceHistory(for scriptHash: String,
                                     entries: [OpalBase.Transaction.History.Entry],
                                     tokenDeltasByHash: [OpalBase.Transaction.Hash: OpalBase.Transaction.History.Record.TokenDelta],
                                     timestamp: Date) -> OpalBase.Transaction.History.ChangeSet {
            let newTransactions = Set(entries.map { $0.transactionHash })
            let previousTransactions = transactionHashesByScriptHash[scriptHash] ?? .init()
            var inserted: [OpalBase.Transaction.Hash: OpalBase.Transaction.History.Record] = .init()
            var updated: [OpalBase.Transaction.Hash: OpalBase.Transaction.History.Record] = .init()
            var removed: Set<OpalBase.Transaction.Hash> = .init()
            
            for entry in entries {
                if var record = records[entry.transactionHash] {
                    let original = record
                    record.resolveUpdate(from: entry, scriptHash: scriptHash, timestamp: timestamp)
                    if let tokenDelta = tokenDeltasByHash[entry.transactionHash] {
                        record.updateTokenDelta(tokenDelta)
                    }
                    records[entry.transactionHash] = record
                    if record != original {
                        updated[entry.transactionHash] = record
                    }
                } else {
                    var record = OpalBase.Transaction.History.Record.makeRecord(for: entry,
                                                                       scriptHash: scriptHash,
                                                                       timestamp: timestamp)
                    if let tokenDelta = tokenDeltasByHash[entry.transactionHash] {
                        record.updateTokenDelta(tokenDelta)
                    }
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
            
            if newTransactions.isEmpty {
                transactionHashesByScriptHash.removeValue(forKey: scriptHash)
            } else {
                transactionHashesByScriptHash[scriptHash] = newTransactions
            }
            
            return OpalBase.Transaction.History.ChangeSet(inserted: Array(inserted.values),
                                                 updated: Array(updated.values),
                                                 removed: Array(removed))
        }
        
        mutating func mergeHistoryEntries(for scriptHash: String,
                                          entries: [OpalBase.Transaction.History.Entry],
                                          tokenDeltasByHash: [OpalBase.Transaction.Hash: OpalBase.Transaction.History.Record.TokenDelta],
                                          timestamp: Date) -> OpalBase.Transaction.History.ChangeSet {
            guard !entries.isEmpty else { return .init() }
            
            var inserted: [OpalBase.Transaction.Hash: OpalBase.Transaction.History.Record] = .init()
            var updated: [OpalBase.Transaction.Hash: OpalBase.Transaction.History.Record] = .init()
            
            for entry in entries {
                if var record = records[entry.transactionHash] {
                    let original = record
                    record.resolveUpdate(from: entry, scriptHash: scriptHash, timestamp: timestamp)
                    if let tokenDelta = tokenDeltasByHash[entry.transactionHash] {
                        record.updateTokenDelta(tokenDelta)
                    }
                    records[entry.transactionHash] = record
                    if record != original {
                        updated[entry.transactionHash] = record
                    }
                } else {
                    var record = OpalBase.Transaction.History.Record.makeRecord(for: entry,
                                                                       scriptHash: scriptHash,
                                                                       timestamp: timestamp)
                    if let tokenDelta = tokenDeltasByHash[entry.transactionHash] {
                        record.updateTokenDelta(tokenDelta)
                    }
                    records[entry.transactionHash] = record
                    inserted[entry.transactionHash] = record
                }
                
                transactionHashesByScriptHash[scriptHash, default: .init()].insert(entry.transactionHash)
            }
            
            return OpalBase.Transaction.History.ChangeSet(inserted: Array(inserted.values),
                                                 updated: Array(updated.values),
                                                 removed: .init())
        }
        
        mutating func updateVerification(for transactionHash: OpalBase.Transaction.Hash,
                                         status: OpalBase.Transaction.History.Status.Verification,
                                         proof: OpalBase.Transaction.MerkleProof?,
                                         verifiedHeight: UInt32?,
                                         timestamp: Date) -> OpalBase.Transaction.History.Record? {
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
        
        mutating func invalidateConfirmations(startingAt height: UInt32,
                                              timestamp: Date) -> [OpalBase.Transaction.History.Record] {
            guard !records.isEmpty else { return .init() }
            let threshold = UInt64(height)
            var updated: [OpalBase.Transaction.History.Record] = .init()
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
        
        mutating func reset() {
            records.removeAll()
            transactionHashesByScriptHash.removeAll()
        }
        
        mutating func store(_ record: OpalBase.Transaction.History.Record) {
            if let existingRecord = records[record.transactionHash] {
                removeTransactionHashFromScriptHashIndexes(
                    for: record.transactionHash,
                    scriptHashes: existingRecord.chainMetadata.scriptHashes
                )
            }

            records[record.transactionHash] = record
            for scriptHash in record.chainMetadata.scriptHashes {
                transactionHashesByScriptHash[scriptHash, default: .init()].insert(record.transactionHash)
            }
        }
        
        var isEmpty: Bool {
            records.isEmpty
        }

        private mutating func removeTransactionHashFromScriptHashIndexes(
            for transactionHash: OpalBase.Transaction.Hash,
            scriptHashes: Set<String>
        ) {
            for scriptHash in scriptHashes {
                transactionHashesByScriptHash[scriptHash]?.remove(transactionHash)
                if transactionHashesByScriptHash[scriptHash]?.isEmpty == true {
                    transactionHashesByScriptHash.removeValue(forKey: scriptHash)
                }
            }
        }
    }
}

extension _OpalBase.Address.Book.TransactionLog: Sendable {}

extension _OpalBase.Address.Book {
    func listTransactionRecords() -> [OpalBase.Transaction.History.Record] {
        transactionLog.listRecords()
    }
    
    func resetTransactionLog() {
        transactionLog.reset()
    }
    
    func storeTransactionRecord(_ record: OpalBase.Transaction.History.Record) {
        transactionLog.store(record)
    }
}
