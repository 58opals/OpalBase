// Network~Account.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    public func resumeQueuedWork(for account: Account) async {
        await ensureTelemetryInstalled(for: account)
        await ensureSynchronization(for: account)
        await account.resumeQueuedRequests()
        await account.resubmitPendingTransactions(using: self)
        await account.processQueuedRequests()
        await account.startNetworkMonitor(using: self)
    }
    
    public func computeCachedBalance(for account: Account) async throws -> Satoshi {
        await ensureTelemetryInstalled(for: account)
        return try await account.loadBalanceFromCache()
    }
    
    public func computeBalance(
        for account: Account,
        priority: TaskPriority? = nil,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> Satoshi {
        await ensureTelemetryInstalled(for: account)
        return try await account.performRequest(for: .calculateBalance,
                                                priority: priority,
                                                retryPolicy: .retry) {
            try await self.ensureSessionReady()
            return try await self.refreshCachedBalance(for: account, options: options)
        }
    }
}

extension Network.FulcrumSession {
    private func usages(for scope: Address.Book.Request.Scope?) -> [DerivationPath.Usage] {
        switch scope {
        case .some(.receiving): return [.receiving]
        case .some(.change): return [.change]
        case .none: return [.receiving, .change]
        }
    }
    
    private func scriptHashes(for account: Account, usage: DerivationPath.Usage) async -> Set<String> {
        let addressBook = await account.addressBook
        let entries = await addressBook.listEntries(for: usage)
        return Set(entries.map { $0.address.makeScriptHash().hexadecimalString })
    }
    
    public func refreshAddressBookUTXOSet(
        for account: Account,
        scope: Address.Book.Request.Scope? = nil,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws {
        await ensureTelemetryInstalled(for: account)
        try await refreshAddressBookUTXOSet(for: account,
                                            scope: scope,
                                            options: options,
                                            scriptHashRefresher: makeScriptHashRefresher(for: account, options: options))
    }
    
    public func scanForUsedAddresses(
        for account: Account,
        scope: Address.Book.Request.Scope? = nil,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws {
        await ensureTelemetryInstalled(for: account)
        for usage in usages(for: scope) {
            try await scanAddressGap(for: account, usage: usage, options: options)
        }
    }
    
    private func filteredRecords(
        _ records: [Address.Book.History.Transaction.Record],
        fromHeight: UInt?,
        toHeight: UInt?,
        includeUnconfirmed: Bool
    ) -> [Address.Book.History.Transaction.Record] {
        records.filter { record in
            if !includeUnconfirmed, record.status != .confirmed { return false }
            if record.height <= 0 { return includeUnconfirmed }
            if let fromHeight, record.height < Int(fromHeight) { return false }
            if let toHeight, record.height > Int(toHeight) { return false }
            return true
        }
    }
    
    public func fetchDetailedTransactions(
        for account: Account,
        scope: Address.Book.Request.Scope,
        fromHeight: UInt? = nil,
        toHeight: UInt? = nil,
        includeUnconfirmed: Bool = true,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> [Address.Book.History.Transaction.Record] {
        await ensureTelemetryInstalled(for: account)
        return try await fetchDetailedTransactions(for: account,
                                                   scope: scope,
                                                   fromHeight: fromHeight,
                                                   toHeight: toHeight,
                                                   includeUnconfirmed: includeUnconfirmed,
                                                   options: options,
                                                   scriptHashRefresher: makeScriptHashRefresher(for: account, options: options))
    }
    
    public func fetchCombinedHistory(
        for account: Account,
        fromHeight: UInt? = nil,
        toHeight: UInt? = nil,
        includeUnconfirmed: Bool = true,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> [Address.Book.History.Transaction.Record] {
        await ensureTelemetryInstalled(for: account)
        try await refreshAddressBookUTXOSet(for: account, scope: nil, options: options)
        let history = await account.addressBook.listTransactionHistory()
        return filteredRecords(history,
                               fromHeight: fromHeight,
                               toHeight: toHeight,
                               includeUnconfirmed: includeUnconfirmed)
    }
    
    func fetchDetailedTransactions(
        for account: Account,
        scope: Address.Book.Request.Scope,
        fromHeight: UInt? = nil,
        toHeight: UInt? = nil,
        includeUnconfirmed: Bool = true,
        options: SwiftFulcrum.Client.Call.Options = .init(),
        scriptHashRefresher: (_ usage: DerivationPath.Usage, _ entry: Address.Book.Entry, _ addressBook: Address.Book) async throws -> Void
    ) async throws -> [Address.Book.History.Transaction.Record] {
        try await refreshAddressBookUTXOSet(for: account,
                                            scope: scope,
                                            options: options,
                                            scriptHashRefresher: scriptHashRefresher)
        let addressBook = await account.addressBook
        let relevantHashes = await scriptHashes(for: account, usage: DerivationPath.Usage(scope: scope))
        let history = await addressBook.listTransactionHistory()
        let filtered = history.filter { !$0.scriptHashes.isDisjoint(with: relevantHashes) }
        return filteredRecords(filtered,
                               fromHeight: fromHeight,
                               toHeight: toHeight,
                               includeUnconfirmed: includeUnconfirmed)
    }
    
    public func fetchCombinedHistoryPage(
        for account: Account,
        fromHeight: UInt? = nil,
        window: UInt,
        includeUnconfirmed: Bool = true,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> [Address.Book.History.Transaction.Record] {
        let history = try await fetchCombinedHistory(for: account,
                                                     fromHeight: fromHeight,
                                                     toHeight: nil,
                                                     includeUnconfirmed: includeUnconfirmed,
                                                     options: options)
        let sorted = history.sorted { lhs, rhs in
            let leftHeight = lhs.height
            let rightHeight = rhs.height
            if leftHeight == rightHeight { return lhs.transactionHash.naturalOrder.lexicographicallyPrecedes(rhs.transactionHash.naturalOrder) }
            if leftHeight <= 0 { return false }
            if rightHeight <= 0 { return true }
            return leftHeight > rightHeight
        }
        return Array(sorted.prefix(Int(window)))
    }
    
    @discardableResult
    public func perform(
        _ request: Address.Book.Request,
        for account: Account,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> Any? {
        await ensureTelemetryInstalled(for: account)
        switch request {
        case .updateCache:
            return try await refreshBalances(for: account,
                                             scope: nil,
                                             forceRefresh: false,
                                             options: options)
        case .updateCacheSubset(let scope):
            return try await refreshBalances(for: account,
                                             scope: scope,
                                             forceRefresh: false,
                                             options: options)
        case .refreshBalances:
            return try await refreshBalances(for: account,
                                             scope: nil,
                                             forceRefresh: true,
                                             options: options)
        case .refreshBalancesSubset(let scope):
            return try await refreshBalances(for: account,
                                             scope: scope,
                                             forceRefresh: true,
                                             options: options)
        case .fetchBalance(let address):
            try ensureSessionReady(allowRestoring: true)
            let addressBook = await account.addressBook
            return try await fetchAndCacheBalance(for: address,
                                                  in: addressBook,
                                                  options: options)
        case .refreshUTXOSet:
            try await refreshAddressBookUTXOSet(for: account, scope: nil, options: options)
            return nil
        case .scanForUsedAddresses:
            try await scanForUsedAddresses(for: account, scope: nil, options: options)
            return nil
        case .refreshUsedStatus:
            return try await refreshAddressUsageStatus(for: account,
                                                       scope: nil,
                                                       options: options,
                                                       shouldScanGap: false)
        case .refreshUsedStatusSubset(let scope):
            return try await refreshAddressUsageStatus(for: account,
                                                       scope: scope,
                                                       options: options,
                                                       shouldScanGap: false)
        case .updateAddressUsageStatus:
            return try await refreshAddressUsageStatus(for: account,
                                                       scope: nil,
                                                       options: options,
                                                       shouldScanGap: true)
        case .updateAddressUsageStatusSubset(let scope):
            return try await refreshAddressUsageStatus(for: account,
                                                       scope: scope,
                                                       options: options,
                                                       shouldScanGap: true)
        case .checkIfUsed(let address):
            return try await checkIfAddressIsUsed(for: account,
                                                  address: address,
                                                  options: options)
        case .fetchCombinedHistory(let fromHeight, let toHeight, let includeUnconfirmed):
            return try await fetchCombinedHistory(for: account,
                                                  fromHeight: fromHeight,
                                                  toHeight: toHeight,
                                                  includeUnconfirmed: includeUnconfirmed,
                                                  options: options)
        case .fetchCombinedHistoryPage(let fromHeight, let window, let includeUnconfirmed):
            return try await fetchCombinedHistoryPage(for: account,
                                                      fromHeight: fromHeight,
                                                      window: window,
                                                      includeUnconfirmed: includeUnconfirmed,
                                                      options: options)
        case .fetchDetailedTransactions(let scope, let fromHeight, let toHeight, let includeUnconfirmed):
            return try await fetchDetailedTransactions(for: account,
                                                       scope: scope,
                                                       fromHeight: fromHeight,
                                                       toHeight: toHeight,
                                                       includeUnconfirmed: includeUnconfirmed,
                                                       options: options)
        }
    }
}

private extension DerivationPath.Usage {
    init(scope: Address.Book.Request.Scope) {
        switch scope {
        case .receiving: self = .receiving
        case .change: self = .change
        }
    }
}

extension Network.FulcrumSession {
    func refreshCachedBalance(
        for account: Account,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> Satoshi {
        try await refreshBalances(for: account,
                                  scope: nil,
                                  forceRefresh: false,
                                  options: options)
    }
    
    private func refreshBalances(
        for account: Account,
        scope: Address.Book.Request.Scope?,
        forceRefresh: Bool,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> Satoshi {
        try ensureSessionReady(allowRestoring: true)
        var aggregate: UInt64 = 0
        try await visitAddressEntries(for: account, scope: scope) { _, entry, addressBook in
            let balance: Satoshi
            if !forceRefresh, entry.cache.isValid {
                balance = entry.cache.balance ?? Satoshi()
            } else {
                balance = try await fetchAndCacheBalance(for: entry.address,
                                                         in: addressBook,
                                                         options: options)
            }
            
            let (updated, didOverflow) = aggregate.addingReportingOverflow(balance.uint64)
            if didOverflow || updated > Satoshi.maximumSatoshi {
                throw Satoshi.Error.exceedsMaximumAmount
            }
            aggregate = updated
        }
        
        return try Satoshi(aggregate)
    }
    
    func refreshAddressUsageStatus(
        for account: Account,
        scope: Address.Book.Request.Scope?,
        options: SwiftFulcrum.Client.Call.Options,
        shouldScanGap: Bool,
        scriptHashRefresher: ((_ usage: DerivationPath.Usage, _ entry: Address.Book.Entry, _ addressBook: Address.Book) async throws -> Void)? = nil
    ) async throws -> [Address] {
        try ensureSessionReady(allowRestoring: true)
        var newlyUsed: [Address] = .init()
        let scriptHashRefresher = scriptHashRefresher ?? makeScriptHashRefresher(for: account, options: options)
        try await visitAddressEntries(for: account, scope: scope) { usage, entry, addressBook in
            let wasUsed = entry.isUsed
            try await scriptHashRefresher(usage, entry, addressBook)
            let isUsed = (try? await addressBook.isUsed(address: entry.address)) ?? wasUsed
            if isUsed && !wasUsed {
                newlyUsed.append(entry.address)
            }
        }
        
        if shouldScanGap {
            try await scanForUsedAddresses(for: account, scope: scope, options: options)
        }
        
        return newlyUsed
    }
    
    func refreshAddressBookUTXOSet(
        for account: Account,
        scope: Address.Book.Request.Scope?,
        options: SwiftFulcrum.Client.Call.Options,
        scriptHashRefresher: (_ usage: DerivationPath.Usage, _ entry: Address.Book.Entry, _ addressBook: Address.Book) async throws -> Void
    ) async throws {
        try await visitAddressEntries(for: account, scope: scope, perform: scriptHashRefresher)
    }
    
    private func visitAddressEntries(
        for account: Account,
        scope: Address.Book.Request.Scope?,
        perform: (_ usage: DerivationPath.Usage, _ entry: Address.Book.Entry, _ addressBook: Address.Book) async throws -> Void
    ) async throws {
        let addressBook = await account.addressBook
        for usage in usages(for: scope) {
            let entries = await addressBook.listEntries(for: usage)
            for entry in entries {
                try await perform(usage, entry, addressBook)
            }
        }
    }
    
    private func refreshEntryScriptHash(
        for account: Account,
        usage: DerivationPath.Usage,
        entry: Address.Book.Entry,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws {
        let scriptHash = entry.address.makeScriptHash().hexadecimalString
        try await executeScriptHashRefresh(for: account,
                                           address: entry.address,
                                           scriptHash: scriptHash,
                                           usage: usage,
                                           options: options)
    }
    
    private func makeScriptHashRefresher(
        for account: Account,
        options: SwiftFulcrum.Client.Call.Options
    ) -> (_ usage: DerivationPath.Usage, _ entry: Address.Book.Entry, _ addressBook: Address.Book) async throws -> Void {
        { usage, entry, _ in
            try await self.refreshEntryScriptHash(for: account,
                                                  usage: usage,
                                                  entry: entry,
                                                  options: options)
        }
    }
    
    private func checkIfAddressIsUsed(
        for account: Account,
        address: Address,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> Bool {
        try ensureSessionReady(allowRestoring: true)
        let addressBook = await account.addressBook
        guard let entry = await addressBook.findEntry(for: address) else {
            throw Address.Book.Error.addressNotFound
        }
        let wasUsed = entry.isUsed
        let scriptHash = address.makeScriptHash().hexadecimalString
        try await executeScriptHashRefresh(for: account,
                                           address: address,
                                           scriptHash: scriptHash,
                                           usage: entry.derivationPath.usage,
                                           options: options)
        return (try? await addressBook.isUsed(address: address)) ?? wasUsed
    }
    
    func fetchAndCacheBalance(
        for address: Address,
        in addressBook: Address.Book,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> Satoshi {
        let response = try await fetchAddressBalance(address.string, options: options)
        let balance = try makeSatoshi(confirmed: response.confirmed, unconfirmed: response.unconfirmed)
        try await addressBook.updateCache(for: address, with: balance)
        return balance
    }
    
    func makeSatoshi(confirmed: UInt64, unconfirmed: Int64) throws -> Satoshi {
        guard let confirmedInt64 = Int64(exactly: confirmed) else {
            throw Satoshi.Error.exceedsMaximumAmount
        }
        let total = confirmedInt64 + unconfirmed
        guard total >= 0 else { return Satoshi() }
        return try Satoshi(UInt64(total))
    }
}
