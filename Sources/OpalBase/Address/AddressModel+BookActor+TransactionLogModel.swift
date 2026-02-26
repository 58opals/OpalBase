// AddressModel+BookActor+TransactionLogModel.swift

import Foundation

extension AddressModel.BookActor {
    struct TransactionLogModel {
        private var records: [TransactionModel.HashModel: TransactionModel.HistoryModel.RecordModel]
        private var transactionHashesByScriptHash: [String: Set<TransactionModel.HashModel>]
        
        init() {
            self.records = .init()
            self.transactionHashesByScriptHash = .init()
        }
        
        func listRecords() -> [TransactionModel.HistoryModel.RecordModel] {
            Array(records.values)
        }
        
        func loadRecord(for transactionHash: TransactionModel.HashModel) -> TransactionModel.HistoryModel.RecordModel? {
            records[transactionHash]
        }
        
        mutating func replaceHistory(for scriptHash: String,
                                     entries: [TransactionModel.HistoryModel.EntryModel],
                                     tokenDeltasByHash: [TransactionModel.HashModel: TransactionModel.HistoryModel.RecordModel.TokenDeltaModel],
                                     timestamp: Date) -> TransactionModel.HistoryModel.ChangeSetModel {
            let newTransactions = Set(entries.map { $0.transactionHash })
            let previousTransactions = transactionHashesByScriptHash[scriptHash] ?? .init()
            var inserted: [TransactionModel.HashModel: TransactionModel.HistoryModel.RecordModel] = .init()
            var updated: [TransactionModel.HashModel: TransactionModel.HistoryModel.RecordModel] = .init()
            var removed: Set<TransactionModel.HashModel> = .init()
            
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
                    var record = TransactionModel.HistoryModel.RecordModel.makeRecord(for: entry,
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
            
            return TransactionModel.HistoryModel.ChangeSetModel(inserted: Array(inserted.values),
                                                 updated: Array(updated.values),
                                                 removed: Array(removed))
        }
        
        mutating func mergeHistoryEntries(for scriptHash: String,
                                          entries: [TransactionModel.HistoryModel.EntryModel],
                                          tokenDeltasByHash: [TransactionModel.HashModel: TransactionModel.HistoryModel.RecordModel.TokenDeltaModel],
                                          timestamp: Date) -> TransactionModel.HistoryModel.ChangeSetModel {
            guard !entries.isEmpty else { return .init() }
            
            var inserted: [TransactionModel.HashModel: TransactionModel.HistoryModel.RecordModel] = .init()
            var updated: [TransactionModel.HashModel: TransactionModel.HistoryModel.RecordModel] = .init()
            
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
                    var record = TransactionModel.HistoryModel.RecordModel.makeRecord(for: entry,
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
            
            return TransactionModel.HistoryModel.ChangeSetModel(inserted: Array(inserted.values),
                                                 updated: Array(updated.values),
                                                 removed: .init())
        }
        
        mutating func updateVerification(for transactionHash: TransactionModel.HashModel,
                                         status: TransactionModel.HistoryModel.StatusModel.Verification,
                                         proof: TransactionModel.MerkleProofModel?,
                                         verifiedHeight: UInt32?,
                                         timestamp: Date) -> TransactionModel.HistoryModel.RecordModel? {
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
                                              timestamp: Date) -> [TransactionModel.HistoryModel.RecordModel] {
            guard !records.isEmpty else { return .init() }
            let threshold = UInt64(height)
            var updated: [TransactionModel.HistoryModel.RecordModel] = .init()
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
        
        mutating func store(_ record: TransactionModel.HistoryModel.RecordModel) {
            records[record.transactionHash] = record
            for scriptHash in record.chainMetadata.scriptHashes {
                transactionHashesByScriptHash[scriptHash, default: .init()].insert(record.transactionHash)
            }
        }
        
        var isEmpty: Bool {
            records.isEmpty
        }
    }
}

extension AddressModel.BookActor.TransactionLogModel: Sendable {}

extension AddressModel.BookActor {
    func listTransactionRecords() -> [TransactionModel.HistoryModel.RecordModel] {
        transactionLog.listRecords()
    }
    
    func resetTransactionLog() {
        transactionLog.reset()
    }
    
    func storeTransactionRecord(_ record: TransactionModel.HistoryModel.RecordModel) {
        transactionLog.store(record)
    }
}
