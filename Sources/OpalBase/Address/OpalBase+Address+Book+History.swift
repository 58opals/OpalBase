// OpalBase+Address+Book+History.swift

import Foundation

extension _OpalBase.Address.Book {
    enum History {}
}

extension _OpalBase.Address.Book.History {
    struct QueryResult: Sendable {
        let address: OpalBase.Address
        let scriptHash: String
        let entries: [OpalBase.Transaction.History.Entry]
    }
    
}

extension _OpalBase.Address.Book {
    func refreshTransactionHistory(using service: OpalBase.Network.AddressReader,
                                          usage: OpalBase.Key.DerivationPath.Usage? = nil,
                                          includeUnconfirmed: Bool = true,
                                          transactionReader: OpalBase.Network.TransactionReader? = nil,
                                          mutationPermit: OpalBase.Network.ChainRefreshMutationPermit? = nil) async throws -> OpalBase.Transaction.History.ChangeSet {
        var aggregatedChangeSet = OpalBase.Transaction.History.ChangeSet()
        var tokenDeltaCache: [OpalBase.Transaction.Hash: OpalBase.Transaction.History.Record.TokenDelta] = .init()
        var entriesByTransactionHash: [OpalBase.Transaction.Hash: OpalBase.Transaction.History.Entry] = .init()
        var resultsByUsage: [[OpalBase.Address.Book.History.QueryResult]] = .init()
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
            try Self.validateConsistentHistoryEntries(in: usageResults,
                                                      entriesByTransactionHash: &entriesByTransactionHash)
            resultsByUsage.append(usageResults)
        }
        
        for usageResults in resultsByUsage {
            if let transactionReader {
                let usageEntries = usageResults.flatMap(\.entries)
                try await updateTokenDeltaCache(for: usageEntries,
                                                transactionReader: transactionReader,
                                                walletScriptHashes: walletScriptHashes,
                                                tokenDeltaCache: &tokenDeltaCache)
            }
        }
        
        let usedUsages = try commitChainRefresh(using: mutationPermit) {
            var usages: Set<OpalBase.Key.DerivationPath.Usage> = []
            for usageResults in resultsByUsage {
                for result in usageResults {
                    if !result.entries.isEmpty {
                        let entry = try inventory.mark(address: result.address, isUsed: true)
                        usages.insert(entry.derivationPath.usage)
                    }
                    let changeSet = transactionLog.replaceHistory(for: result.scriptHash,
                                                                  entries: result.entries,
                                                                  tokenDeltasByHash: tokenDeltaCache,
                                                                  timestamp: refreshTimestamp)
                    aggregatedChangeSet.merge(changeSet)
                }
            }
            return usages
        }
        for usage in usedUsages { try await generateEntriesIfNeeded(for: usage) }

        return aggregatedChangeSet
    }

    func refreshTransactionHistory(using service: any OpalBase.Network.AddressReadable,
                                   usage: OpalBase.Key.DerivationPath.Usage? = nil,
                                   includeUnconfirmed: Bool = true,
                                   transactionReader: (any OpalBase.Network.TransactionReadableClient)? = nil) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await refreshTransactionHistory(using: .init(service),
                                            usage: usage,
                                            includeUnconfirmed: includeUnconfirmed,
                                            transactionReader: transactionReader.map(OpalBase.Network.TransactionReader.init(_:)))
    }
}

extension _OpalBase.Address.Book {
    func refreshTransactionHistory(for address: OpalBase.Address,
                                          using service: OpalBase.Network.AddressReader,
                                          includeUnconfirmed: Bool,
                                          transactionReader: OpalBase.Network.TransactionReader? = nil,
                                          mutationPermit: OpalBase.Network.ChainRefreshMutationPermit? = nil) async throws -> OpalBase.Transaction.History.ChangeSet {
        guard contains(address: address) else { throw Error.addressNotFound }
        
        let scriptHash = address.makeScriptHash().hexadecimalString
        let result = try await fetchHistoryQueryResult(for: address,
                                                       scriptHash: scriptHash,
                                                       using: service,
                                                       includeUnconfirmed: includeUnconfirmed)
        let timestamp = Date.now
        var tokenDeltaCache: [OpalBase.Transaction.Hash: OpalBase.Transaction.History.Record.TokenDelta] = .init()
        if let transactionReader {
            let walletScriptHashes = listWalletScriptHashes()
            try await updateTokenDeltaCache(for: result.entries,
                                            transactionReader: transactionReader,
                                            walletScriptHashes: walletScriptHashes,
                                            tokenDeltaCache: &tokenDeltaCache)
        }
        let (changeSet, usage) = try commitChainRefresh(using: mutationPermit) {
            let entry = result.entries.isEmpty ? nil : try inventory.mark(address: address, isUsed: true)
            let changeSet = transactionLog.replaceHistory(for: result.scriptHash,
                                                         entries: result.entries,
                                                         tokenDeltasByHash: tokenDeltaCache,
                                                         timestamp: timestamp)
            return (changeSet, entry?.derivationPath.usage)
        }
        if let usage { try await generateEntriesIfNeeded(for: usage) }
        return changeSet
    }

    func refreshTransactionHistory(for address: OpalBase.Address,
                                   using service: any OpalBase.Network.AddressReadable,
                                   includeUnconfirmed: Bool,
                                   transactionReader: (any OpalBase.Network.TransactionReadableClient)? = nil) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await refreshTransactionHistory(for: address,
                                            using: .init(service),
                                            includeUnconfirmed: includeUnconfirmed,
                                            transactionReader: transactionReader.map(OpalBase.Network.TransactionReader.init(_:)))
    }
}

private extension _OpalBase.Address.Book {
    func fetchHistoryQueryResult(
        for address: OpalBase.Address,
        scriptHash: String,
        using service: OpalBase.Network.AddressReader,
        includeUnconfirmed: Bool
    ) async throws -> OpalBase.Address.Book.History.QueryResult {
        do {
            let history = try await service.fetchHistory(for: address.string,
                                                         includeUnconfirmed: includeUnconfirmed)
            let mappedEntries = try history.map { try $0.makeHistoryEntry() }
            var seenTransactionHashes: Set<OpalBase.Transaction.Hash> = .init()
            for entry in mappedEntries where !seenTransactionHashes.insert(entry.transactionHash).inserted {
                throw OpalBase.Network.Error(
                    reason: .protocolViolation,
                    message: "History response contained duplicate transaction identifiers"
                )
            }
            if !includeUnconfirmed, mappedEntries.contains(where: { $0.height <= 0 }) {
                throw OpalBase.Network.Error(
                    reason: .protocolViolation,
                    message: "Confirmed-only history response included an unconfirmed transaction"
                )
            }
            return OpalBase.Address.Book.History.QueryResult(address: address,
                                                    scriptHash: scriptHash,
                                                    entries: mappedEntries)
        } catch {
            if error.isCancellationError {
                throw error
            }
            throw OpalBase.Address.Book.Error.transactionHistoryRefreshFailed(address, error)
        }
    }

    static func validateConsistentHistoryEntries(
        in results: [OpalBase.Address.Book.History.QueryResult],
        entriesByTransactionHash: inout [OpalBase.Transaction.Hash: OpalBase.Transaction.History.Entry]
    ) throws {
        for result in results {
            for entry in result.entries {
                guard let existing = entriesByTransactionHash[entry.transactionHash] else {
                    entriesByTransactionHash[entry.transactionHash] = entry
                    continue
                }

                guard existing.height == entry.height else {
                    throw OpalBase.Address.Book.Error.transactionHistoryRefreshFailed(
                        result.address,
                        OpalBase.Network.Error(
                            reason: .protocolViolation,
                            message: "History response contained conflicting transaction heights"
                        )
                    )
                }
                guard existing.fee == entry.fee else {
                    throw OpalBase.Address.Book.Error.transactionHistoryRefreshFailed(
                        result.address,
                        OpalBase.Network.Error(
                            reason: .protocolViolation,
                            message: "History response contained conflicting transaction fees"
                        )
                    )
                }
            }
        }
    }
}

extension _OpalBase.Address.Book {
    func updateTransactionConfirmations(using handler: OpalBase.Network.TransactionClient,
                                               for transactionHashes: [OpalBase.Transaction.Hash],
                                               mutationPermit: OpalBase.Network.ChainRefreshMutationPermit? = nil) async throws -> OpalBase.Transaction.History.ChangeSet {
        guard !transactionHashes.isEmpty else { return .init() }
        
        let uniqueTransactionHashes = transactionHashes.deduplicate()
        var recordsToUpdate: [OpalBase.Transaction.History.Record] = .init()
        for transactionHash in uniqueTransactionHashes {
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
            guard status.transactionHash == record.transactionHash else {
                throw OpalBase.Network.Error(
                    reason: .protocolViolation,
                    message: "Confirmation status hash mismatch"
                )
            }
            try status.validateConsistency()
            return (record: record, status: status)
        }
        
        var aggregatedChangeSet = OpalBase.Transaction.History.ChangeSet()
        let refreshTimestamp = Date.now
        var entriesByScriptHash: [String: [OpalBase.Transaction.History.Entry]] = .init()
        entriesByScriptHash.reserveCapacity(updates.count)
        
        for update in updates {
            let resolvedHeight = update.status.transactionHeight ?? -1
            let entry = OpalBase.Transaction.History.Entry(
                transactionHash: update.record.transactionHash,
                height: resolvedHeight,
                fee: update.record.chainMetadata.fee
            )
            for scriptHash in update.record.chainMetadata.scriptHashes {
                entriesByScriptHash[scriptHash, default: .init()].append(entry)
            }
        }
        
        try commitChainRefresh(using: mutationPermit) {
            for (scriptHash, entries) in entriesByScriptHash {
                let changeSet = transactionLog.mergeHistoryEntries(
                    for: scriptHash,
                    entries: entries,
                    tokenDeltasByHash: .init(),
                    timestamp: refreshTimestamp
                )
                aggregatedChangeSet.merge(changeSet)
            }
        }
        
        return aggregatedChangeSet
    }

    func updateTransactionConfirmations(using handler: any OpalBase.Network.TransactionConfirmationClient,
                                        for transactionHashes: [OpalBase.Transaction.Hash]) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await updateTransactionConfirmations(using: .init(confirmations: handler), for: transactionHashes)
    }
    
    func refreshTransactionConfirmations(using handler: OpalBase.Network.TransactionClient,
                                         mutationPermit: OpalBase.Network.ChainRefreshMutationPermit? = nil) async throws -> OpalBase.Transaction.History.ChangeSet {
        let records = transactionLog.listRecords()
        guard !records.isEmpty else { return .init() }
        let transactionHashes = records.map(\.transactionHash)
        return try await updateTransactionConfirmations(using: handler, for: transactionHashes, mutationPermit: mutationPermit)
    }

    func refreshTransactionConfirmations(using handler: any OpalBase.Network.TransactionConfirmationClient) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await refreshTransactionConfirmations(using: .init(confirmations: handler))
    }

}
