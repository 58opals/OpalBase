// Network+FulcrumSession~Account.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    public func resumeQueuedWork(for account: Account) async {
        await ensureTelemetryInstalled(for: account)
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
    func refreshCachedBalance(
        for account: Account,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> Satoshi {
        let addressBook = await account.addressBook
        let usages: [DerivationPath.Usage] = [.receiving, .change]
        
        var aggregate: UInt64 = 0
        for usage in usages {
            let entries = await addressBook.listEntries(for: usage)
            for entry in entries {
                let resolvedBalance: Satoshi
                if entry.cache.isValid, let cachedBalance = entry.cache.balance {
                    resolvedBalance = cachedBalance
                } else if entry.cache.isValid {
                    resolvedBalance = Satoshi()
                } else {
                    resolvedBalance = try await fetchAndCacheBalance(
                        for: entry.address,
                        in: addressBook,
                        options: options
                    )
                }
                
                let (updated, didOverflow) = aggregate.addingReportingOverflow(resolvedBalance.uint64)
                if didOverflow || updated > Satoshi.maximumSatoshi {
                    throw Satoshi.Error.exceedsMaximumAmount
                }
                aggregate = updated
            }
        }
        
        return try Satoshi(aggregate)
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
