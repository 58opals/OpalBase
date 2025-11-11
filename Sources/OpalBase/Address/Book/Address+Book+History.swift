// Address+Book+History.swift

import Foundation

extension Address.Book {
    enum History {}
}

extension Address.Book.History {
    struct QueryResult: Sendable {
        let address: Address
        let scriptHash: String
        let entries: [Transaction.History.Entry]
    }
    
    struct ConfirmationUpdate: Sendable {
        let record: Transaction.History.Record
        let status: Network.TransactionConfirmationStatus
    }
}

extension Address.Book {
    public func refreshTransactionHistory(using service: Network.AddressReadable,
                                          usage: DerivationPath.Usage? = nil,
                                          includeUnconfirmed: Bool = true) async throws -> Transaction.History.ChangeSet {
        let targetUsages = usage.map { [$0] } ?? DerivationPath.Usage.allCases
        var aggregatedChangeSet = Transaction.History.ChangeSet()
        
        for currentUsage in targetUsages {
            let entries = listEntries(for: currentUsage)
            guard !entries.isEmpty else { continue }
            
            let usageResults = try await withThrowingTaskGroup(of: Address.Book.History.QueryResult.self) { group in
                for entry in entries {
                    group.addTask {
                        try Task.checkCancellation()
                        do {
                            let history = try await service.fetchHistory(for: entry.address.string,
                                                                         includeUnconfirmed: includeUnconfirmed)
                            let mappedEntries = try history.map { try $0.makeHistoryEntry() }
                            let scriptHash = entry.address.makeScriptHash().hexadecimalString
                            return Address.Book.History.QueryResult(address: entry.address,
                                                                    scriptHash: scriptHash,
                                                                    entries: mappedEntries)
                        } catch {
                            throw Address.Book.Error.transactionHistoryRefreshFailed(entry.address, error)
                        }
                    }
                }
                
                var results: [Address.Book.History.QueryResult] = .init()
                for try await result in group {
                    results.append(result)
                }
                return results
            }
            
            for result in usageResults {
                if !result.entries.isEmpty {
                    try await mark(address: result.address, isUsed: true)
                }
                
                let timestamp = Date()
                let changeSet = transactionLog.updateHistory(for: result.scriptHash,
                                                             entries: result.entries,
                                                             timestamp: timestamp)
                aggregatedChangeSet.inserted.append(contentsOf: changeSet.inserted)
                aggregatedChangeSet.updated.append(contentsOf: changeSet.updated)
                aggregatedChangeSet.removed.append(contentsOf: changeSet.removed)
            }
        }
        
        return aggregatedChangeSet
    }
}

extension Address.Book {
    public func updateTransactionConfirmations(using handler: Network.TransactionConfirming,
                                               for transactionHashes: [Transaction.Hash]) async throws -> Transaction.History.ChangeSet {
        guard !transactionHashes.isEmpty else { return .init() }
        
        let uniqueHashes = Set(transactionHashes)
        var recordsToUpdate: [Transaction.History.Record] = .init()
        for transactionHash in uniqueHashes {
            guard let record = transactionLog.loadRecord(for: transactionHash) else { continue }
            recordsToUpdate.append(record)
        }
        guard !recordsToUpdate.isEmpty else { return .init() }
        
        let updates = try await withThrowingTaskGroup(of: Address.Book.History.ConfirmationUpdate.self) { group in
            for record in recordsToUpdate {
                group.addTask {
                    try Task.checkCancellation()
                    do {
                        let status = try await handler.fetchConfirmationStatus(for: record.transactionHash)
                        return Address.Book.History.ConfirmationUpdate(record: record, status: status)
                    } catch {
                        throw Address.Book.Error.transactionConfirmationRefreshFailed(record.transactionHash, error)
                    }
                }
            }
            
            var collected: [Address.Book.History.ConfirmationUpdate] = .init()
            for try await update in group {
                collected.append(update)
            }
            return collected
        }
        
        var aggregatedChangeSet = Transaction.History.ChangeSet()
        for update in updates {
            let resolvedHeight = update.status.transactionHeight ?? -1
            let entry = Transaction.History.Entry(transactionHash: update.record.transactionHash,
                                                  height: resolvedHeight,
                                                  fee: update.record.chainMetadata.fee)
            let timestamp = Date()
            for scriptHash in update.record.chainMetadata.scriptHashes {
                let changeSet = transactionLog.updateHistory(for: scriptHash,
                                                             entries: [entry],
                                                             timestamp: timestamp)
                aggregatedChangeSet.inserted.append(contentsOf: changeSet.inserted)
                aggregatedChangeSet.updated.append(contentsOf: changeSet.updated)
                aggregatedChangeSet.removed.append(contentsOf: changeSet.removed)
            }
        }
        
        return aggregatedChangeSet
    }
    
    public func refreshTransactionConfirmations(using handler: Network.TransactionConfirming) async throws -> Transaction.History.ChangeSet {
        let records = transactionLog.listRecords()
        guard !records.isEmpty else { return .init() }
        let hashes = records.map(\.transactionHash)
        return try await updateTransactionConfirmations(using: handler, for: hashes)
    }
}
