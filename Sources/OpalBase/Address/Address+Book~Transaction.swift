// Address+Book~Transaction.swift

import Foundation

extension Address.Book {
    public func listTransactionHistory() -> [History.Transaction.Record] {
        Array(transactionHistories.values)
    }
    
    func updateTransactionHistory(for scriptHash: String,
                                  entries: [History.Transaction.Entry],
                                  timestamp: Date = .now) {
        let newTransactions = Set(entries.map { $0.transactionHash })
        let previousTransactions = scriptHashToTransactions[scriptHash] ?? .init()
        
        scriptHashToTransactions[scriptHash] = newTransactions
        
        for entry in entries {
            var record = transactionHistories[entry.transactionHash]
            if record == nil {
                record = History.Transaction.Record(transactionHash: entry.transactionHash,
                                                    height: entry.height,
                                                    fee: entry.fee,
                                                    scriptHashes: [scriptHash],
                                                    firstSeenAt: timestamp,
                                                    lastUpdatedAt: timestamp)
            } else {
                record?.height = entry.height
                record?.fee = entry.fee
                record?.lastUpdatedAt = timestamp
                record?.scriptHashes.insert(scriptHash)
            }
            
            if let updatedRecord = record {
                transactionHistories[entry.transactionHash] = updatedRecord
            }
        }
        
        let removedTransactions = previousTransactions.subtracting(newTransactions)
        for hash in removedTransactions {
            guard var record = transactionHistories[hash] else { continue }
            record.scriptHashes.remove(scriptHash)
            record.lastUpdatedAt = timestamp
            if record.scriptHashes.isEmpty {
                transactionHistories.removeValue(forKey: hash)
            } else {
                transactionHistories[hash] = record
            }
        }
    }
}
