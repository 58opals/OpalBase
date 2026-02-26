// AddressModel+BookActor+HistoryModel.swift

import Foundation

extension AddressModel.BookActor {
    enum HistoryModel {}
}

extension AddressModel.BookActor.HistoryModel {
    struct QueryResultModel: Sendable {
        let address: AddressModel
        let scriptHash: String
        let entries: [TransactionModel.HistoryModel.EntryModel]
    }
    
    struct ConfirmationUpdateModel: Sendable {
        let record: TransactionModel.HistoryModel.RecordModel
        let status: NetworkModel.TransactionConfirmationStatusModel
    }
}

extension AddressModel.BookActor {
    public func refreshTransactionHistory(using service: NetworkModel.AddressReadable,
                                          usage: DerivationPathModel.UsageModel? = nil,
                                          includeUnconfirmed: Bool = true,
                                          transactionReader: NetworkModel.TransactionReadableClient? = nil) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
        var aggregatedChangeSet = TransactionModel.HistoryModel.ChangeSetModel()
        var tokenDeltaCache: [TransactionModel.HashModel: TransactionModel.HistoryModel.RecordModel.TokenDeltaModel] = .init()
        let walletScriptHashes = listWalletScriptHashes()
        
        let refreshTimestamp = Date.now
        try await performForEachTargetUsage(usage) { _, entries in
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
            
            if let transactionReader {
                let usageEntries = usageResults.flatMap(\.entries)
                try await updateTokenDeltaCache(for: usageEntries,
                                                transactionReader: transactionReader,
                                                walletScriptHashes: walletScriptHashes,
                                                tokenDeltaCache: &tokenDeltaCache)
            }
            
            for result in usageResults {
                if !result.entries.isEmpty {
                    try await mark(address: result.address, isUsed: true)
                }
                
                let changeSet = transactionLog.replaceHistory(for: result.scriptHash,
                                                              entries: result.entries,
                                                              tokenDeltasByHash: tokenDeltaCache,
                                                              timestamp: refreshTimestamp)
                aggregatedChangeSet.merge(changeSet)
            }
        }
        
        return aggregatedChangeSet
    }
}

extension AddressModel.BookActor {
    public func refreshTransactionHistory(for address: AddressModel,
                                          using service: NetworkModel.AddressReadable,
                                          includeUnconfirmed: Bool,
                                          transactionReader: NetworkModel.TransactionReadableClient? = nil) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
        
        let scriptHash = address.makeScriptHash().hexadecimalString
        let result = try await fetchHistoryQueryResult(for: address,
                                                       scriptHash: scriptHash,
                                                       using: service,
                                                       includeUnconfirmed: includeUnconfirmed)
        if !result.entries.isEmpty {
            try await mark(address: address, isUsed: true)
        }
        
        let timestamp = Date.now
        var tokenDeltaCache: [TransactionModel.HashModel: TransactionModel.HistoryModel.RecordModel.TokenDeltaModel] = .init()
        if let transactionReader {
            let walletScriptHashes = listWalletScriptHashes()
            try await updateTokenDeltaCache(for: result.entries,
                                            transactionReader: transactionReader,
                                            walletScriptHashes: walletScriptHashes,
                                            tokenDeltaCache: &tokenDeltaCache)
        }
        return transactionLog.replaceHistory(for: result.scriptHash,
                                             entries: result.entries,
                                             tokenDeltasByHash: tokenDeltaCache,
                                             timestamp: timestamp)
    }
}

private extension AddressModel.BookActor {
    func fetchHistoryQueryResult(
        for address: AddressModel,
        scriptHash: String,
        using service: NetworkModel.AddressReadable,
        includeUnconfirmed: Bool
    ) async throws -> AddressModel.BookActor.HistoryModel.QueryResultModel {
        do {
            let history = try await service.fetchHistory(for: address.string,
                                                         includeUnconfirmed: includeUnconfirmed)
            let mappedEntries = try history.map { try $0.makeHistoryEntry() }
            return AddressModel.BookActor.HistoryModel.QueryResultModel(address: address,
                                                    scriptHash: scriptHash,
                                                    entries: mappedEntries)
        } catch {
            throw AddressModel.BookActor.Error.transactionHistoryRefreshFailed(address, error)
        }
    }
}

extension AddressModel.BookActor {
    public func updateTransactionConfirmations(using handler: NetworkModel.TransactionConfirmationClient,
                                               for transactionHashes: [TransactionModel.HashModel]) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
        guard !transactionHashes.isEmpty else { return .init() }
        
        let uniqueHashes = transactionHashes.deduplicate()
        var recordsToUpdate: [TransactionModel.HistoryModel.RecordModel] = .init()
        for transactionHash in uniqueHashes {
            guard let record = transactionLog.loadRecord(for: transactionHash) else { continue }
            recordsToUpdate.append(record)
        }
        guard !recordsToUpdate.isEmpty else { return .init() }
        
        let updates = try await recordsToUpdate.mapConcurrently(
            transformError: { record, error in
                AddressModel.BookActor.Error.transactionConfirmationRefreshFailed(record.transactionHash, error)
            }
        ) { record in
            let status = try await handler.fetchConfirmationStatus(for: record.transactionHash)
            return AddressModel.BookActor.HistoryModel.ConfirmationUpdateModel(record: record, status: status)
        }
        
        var aggregatedChangeSet = TransactionModel.HistoryModel.ChangeSetModel()
        let refreshTimestamp = Date.now
        var entriesByScriptHash: [String: [TransactionModel.HistoryModel.EntryModel]] = .init()
        entriesByScriptHash.reserveCapacity(updates.count)
        
        for update in updates {
            let resolvedHeight = update.status.transactionHeight ?? -1
            let entry = TransactionModel.HistoryModel.EntryModel(
                transactionHash: update.record.transactionHash,
                height: resolvedHeight,
                fee: update.record.chainMetadata.fee
            )
            for scriptHash in update.record.chainMetadata.scriptHashes {
                entriesByScriptHash[scriptHash, default: .init()].append(entry)
            }
        }
        
        for (scriptHash, entries) in entriesByScriptHash {
            let changeSet = transactionLog.mergeHistoryEntries(
                for: scriptHash,
                entries: entries,
                tokenDeltasByHash: .init(),
                timestamp: refreshTimestamp
            )
            aggregatedChangeSet.merge(changeSet)
        }
        
        return aggregatedChangeSet
    }
    
    public func refreshTransactionConfirmations(using handler: NetworkModel.TransactionConfirmationClient) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
        let records = transactionLog.listRecords()
        guard !records.isEmpty else { return .init() }
        let hashes = records.map(\.transactionHash)
        return try await updateTransactionConfirmations(using: handler, for: hashes)
    }
}
