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
        var aggregatedChangeSet = Transaction.History.ChangeSet()
        
        let refreshTimestamp = Date.now
        try await forEachTargetUsage(usage) { _, entries in
            let targets = entries.map { entry in
                let address = entry.address
                let scriptHash = address.makeScriptHash().hexadecimalString
                return (address: address, scriptHash: scriptHash)
            }
            let usageResults = try await targets.mapConcurrently { target in
                try await self.fetchHistoryQueryResult(for: target.address,
                                                       scriptHash: target.scriptHash,
                                                       using: service,
                                                       includeUnconfirmed: includeUnconfirmed)
            }
            
            for result in usageResults {
                if !result.entries.isEmpty {
                    try await mark(address: result.address, isUsed: true)
                }
                
                let changeSet = transactionLog.replaceHistory(for: result.scriptHash,
                                                              entries: result.entries,
                                                              timestamp: refreshTimestamp)
                aggregatedChangeSet.merge(changeSet)
            }
        }
        
        return aggregatedChangeSet
    }
}

extension Address.Book {
    public func refreshTransactionHistory(for address: Address,
                                          using service: Network.AddressReadable,
                                          includeUnconfirmed: Bool) async throws -> Transaction.History.ChangeSet {
        let scriptHash = address.makeScriptHash().hexadecimalString
        let result = try await fetchHistoryQueryResult(for: address,
                                                       scriptHash: scriptHash,
                                                       using: service,
                                                       includeUnconfirmed: includeUnconfirmed)
        if !result.entries.isEmpty {
            try await mark(address: address, isUsed: true)
        }
        
        let timestamp = Date.now
        return transactionLog.replaceHistory(for: result.scriptHash,
                                             entries: result.entries,
                                             timestamp: timestamp)
    }
}

private extension Address.Book {
    func fetchHistoryQueryResult(
        for address: Address,
        scriptHash: String,
        using service: Network.AddressReadable,
        includeUnconfirmed: Bool
    ) async throws -> Address.Book.History.QueryResult {
        do {
            let history = try await service.fetchHistory(for: address.string,
                                                         includeUnconfirmed: includeUnconfirmed)
            let mappedEntries = try history.map { try $0.makeHistoryEntry() }
            return Address.Book.History.QueryResult(address: address,
                                                    scriptHash: scriptHash,
                                                    entries: mappedEntries)
        } catch {
            throw Address.Book.Error.transactionHistoryRefreshFailed(address, error)
        }
    }
}

extension Address.Book {
    public func updateTransactionConfirmations(using handler: Network.TransactionConfirming,
                                               for transactionHashes: [Transaction.Hash]) async throws -> Transaction.History.ChangeSet {
        guard !transactionHashes.isEmpty else { return .init() }
        
        let uniqueHashes = transactionHashes.uniqued()
        var recordsToUpdate: [Transaction.History.Record] = .init()
        for transactionHash in uniqueHashes {
            guard let record = transactionLog.loadRecord(for: transactionHash) else { continue }
            recordsToUpdate.append(record)
        }
        guard !recordsToUpdate.isEmpty else { return .init() }
        
        let updates = try await recordsToUpdate.mapConcurrently(
            transformError: { record, error in
                Address.Book.Error.transactionConfirmationRefreshFailed(record.transactionHash, error)
            }
        ) { record in
            let status = try await handler.fetchConfirmationStatus(for: record.transactionHash)
            return Address.Book.History.ConfirmationUpdate(record: record, status: status)
        }
        
        var aggregatedChangeSet = Transaction.History.ChangeSet()
        let refreshTimestamp = Date.now
        for update in updates {
            let resolvedHeight = update.status.transactionHeight ?? -1
            let entry = Transaction.History.Entry(transactionHash: update.record.transactionHash,
                                                  height: resolvedHeight,
                                                  fee: update.record.chainMetadata.fee)
            for scriptHash in update.record.chainMetadata.scriptHashes {
                let changeSet = transactionLog.mergeHistoryEntries(for: scriptHash,
                                                                   entries: [entry],
                                                                   timestamp: refreshTimestamp)
                aggregatedChangeSet.merge(changeSet)
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
