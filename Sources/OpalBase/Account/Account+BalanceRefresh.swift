// Account+BalanceRefresh.swift

import Foundation

extension Account {
    public struct BalanceRefresh: Sendable {
        public let balancesByUsage: [DerivationPath.Usage: [Address: Satoshi]]
        public let total: Satoshi
        
        public init(balancesByUsage: [DerivationPath.Usage: [Address: Satoshi]], total: Satoshi) {
            self.balancesByUsage = balancesByUsage
            self.total = total
        }
    }
}

extension Account {
    public func refreshBalances(for usage: DerivationPath.Usage? = nil,
                                loader: @escaping @Sendable (Address) async throws -> Satoshi) async throws -> BalanceRefresh {
        let targetUsages = DerivationPath.Usage.resolveTargetUsages(for: usage)
        var balancesByUsage: [DerivationPath.Usage: [Address: Satoshi]] = .init()
        let refreshTimestamp = Date.now
        
        for currentUsage in targetUsages {
            let entries = await addressBook.listEntries(for: currentUsage)
            
            guard !entries.isEmpty else {
                balancesByUsage[currentUsage] = .init()
                continue
            }
            
            let addresses = entries.map(\.address)
            let usageResults = try await addresses.mapConcurrently(
                transformError: { address, error in
                    Error.balanceRefreshFailed(address, error)
                }
            ) { address in
                let balance = try await loader(address)
                return (address, balance)
            }
            
            let usageBalances = Dictionary(uniqueKeysWithValues: usageResults)
            
            do {
                try await addressBook.updateCachedBalances(usageBalances, timestamp: refreshTimestamp)
            } catch let error as Address.Book.Error {
                throw Self.makeAccountError(from: error)
            }
            balancesByUsage[currentUsage] = usageBalances
        }
        
        let total = try balancesByUsage.values.reduce(Satoshi()) { partial, balances in
            let usageTotal = try balances.values.sumSatoshi(or: Error.paymentExceedsMaximumAmount)
            return try partial + usageTotal
        }
        
        return BalanceRefresh(balancesByUsage: balancesByUsage, total: total)
    }
}
