// OpalBase.Address+BookActor+HistoryModel.swift

import Foundation

extension _OpalBase.Address.Book {
    enum HistoryModel {}
}

extension _OpalBase.Address.Book.HistoryModel {
    struct QueryResultModel: Sendable {
        let address: OpalBase.Address
        let scriptHash: String
        let entries: [OpalBase.Transaction.HistoryModel.EntryModel]
    }
    
    struct ConfirmationUpdateModel: Sendable {
        let record: OpalBase.Transaction.HistoryModel.RecordModel
        let status: OpalBase.Network.TransactionConfirmationStatus
    }
}

extension _OpalBase.Address.Book {
    public func refreshTransactionHistory(using service: OpalBase.Network.AddressReadable,
                                          usage: OpalBase.DerivationPath.UsageModel? = nil,
                                          includeUnconfirmed: Bool = true,
                                          transactionReader: OpalBase.Network.TransactionReadableClient? = nil) async throws -> OpalBase.Transaction.HistoryModel.ChangeSetModel {
        var aggregatedChangeSet = OpalBase.Transaction.HistoryModel.ChangeSetModel()
        var tokenDeltaCache: [OpalBase.Transaction.HashModel: OpalBase.Transaction.HistoryModel.RecordModel.TokenDeltaModel] = .init()
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

extension _OpalBase.Address.Book {
    public func refreshTransactionHistory(for address: OpalBase.Address,
                                          using service: OpalBase.Network.AddressReadable,
                                          includeUnconfirmed: Bool,
                                          transactionReader: OpalBase.Network.TransactionReadableClient? = nil) async throws -> OpalBase.Transaction.HistoryModel.ChangeSetModel {
        
        let scriptHash = address.makeScriptHash().hexadecimalString
        let result = try await fetchHistoryQueryResult(for: address,
                                                       scriptHash: scriptHash,
                                                       using: service,
                                                       includeUnconfirmed: includeUnconfirmed)
        if !result.entries.isEmpty {
            try await mark(address: address, isUsed: true)
        }
        
        let timestamp = Date.now
        var tokenDeltaCache: [OpalBase.Transaction.HashModel: OpalBase.Transaction.HistoryModel.RecordModel.TokenDeltaModel] = .init()
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

private extension _OpalBase.Address.Book {
    func fetchHistoryQueryResult(
        for address: OpalBase.Address,
        scriptHash: String,
        using service: OpalBase.Network.AddressReadable,
        includeUnconfirmed: Bool
    ) async throws -> OpalBase.Address.Book.HistoryModel.QueryResultModel {
        do {
            let history = try await service.fetchHistory(for: address.string,
                                                         includeUnconfirmed: includeUnconfirmed)
            let mappedEntries = try history.map { try $0.makeHistoryEntry() }
            return OpalBase.Address.Book.HistoryModel.QueryResultModel(address: address,
                                                    scriptHash: scriptHash,
                                                    entries: mappedEntries)
        } catch {
            throw OpalBase.Address.Book.Error.transactionHistoryRefreshFailed(address, error)
        }
    }
}

extension _OpalBase.Address.Book {
    public func updateTransactionConfirmations(using handler: OpalBase.Network.TransactionConfirmationClient,
                                               for transactionHashes: [OpalBase.Transaction.HashModel]) async throws -> OpalBase.Transaction.HistoryModel.ChangeSetModel {
        guard !transactionHashes.isEmpty else { return .init() }
        
        let uniqueHashes = transactionHashes.deduplicate()
        var recordsToUpdate: [OpalBase.Transaction.HistoryModel.RecordModel] = .init()
        for transactionHash in uniqueHashes {
            guard let record = transactionLog.loadRecord(for: transactionHash) else { continue }
            recordsToUpdate.append(record)
        }
        guard !recordsToUpdate.isEmpty else { return .init() }
        
        let updates = try await recordsToUpdate.mapConcurrently(
            transformError: { record, error in
                OpalBase.Address.Book.Error.transactionConfirmationRefreshFailed(record.transactionHash, error)
            }
        ) { record in
            let status = try await handler.fetchConfirmationStatus(for: record.transactionHash)
            return OpalBase.Address.Book.HistoryModel.ConfirmationUpdateModel(record: record, status: status)
        }
        
        var aggregatedChangeSet = OpalBase.Transaction.HistoryModel.ChangeSetModel()
        let refreshTimestamp = Date.now
        var entriesByScriptHash: [String: [OpalBase.Transaction.HistoryModel.EntryModel]] = .init()
        entriesByScriptHash.reserveCapacity(updates.count)
        
        for update in updates {
            let resolvedHeight = update.status.transactionHeight ?? -1
            let entry = OpalBase.Transaction.HistoryModel.EntryModel(
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
    
    public func refreshTransactionConfirmations(using handler: OpalBase.Network.TransactionConfirmationClient) async throws -> OpalBase.Transaction.HistoryModel.ChangeSetModel {
        let records = transactionLog.listRecords()
        guard !records.isEmpty else { return .init() }
        let hashes = records.map(\.transactionHash)
        return try await updateTransactionConfirmations(using: handler, for: hashes)
    }
}
