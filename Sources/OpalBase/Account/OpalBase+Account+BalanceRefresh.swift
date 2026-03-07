// OpalBase.Account+BalanceRefresh.swift

import Foundation

extension _OpalBase.Account {
    public struct BalanceRefresh: Sendable {
        public let balancesByUsage: [OpalBase.DerivationPath.UsageModel: [OpalBase.Address: OpalBase.Satoshi]]
        public let total: OpalBase.Satoshi
        
        public init(balancesByUsage: [OpalBase.DerivationPath.UsageModel: [OpalBase.Address: OpalBase.Satoshi]], total: OpalBase.Satoshi) {
            self.balancesByUsage = balancesByUsage
            self.total = total
        }
    }
}

extension _OpalBase.Account {
    public func refreshBalances(for usage: OpalBase.DerivationPath.UsageModel? = nil,
                                loader: @escaping @Sendable (OpalBase.Address) async throws -> OpalBase.Satoshi) async throws -> BalanceRefresh {
        let targetUsages = OpalBase.DerivationPath.UsageModel.resolveTargetUsages(for: usage)
        var balancesByUsage: [OpalBase.DerivationPath.UsageModel: [OpalBase.Address: OpalBase.Satoshi]] = .init()
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
            
            try await mapAddressBookError {
                try await addressBook.updateCachedBalances(usageBalances, timestamp: refreshTimestamp)
            }
            balancesByUsage[currentUsage] = usageBalances
        }
        
        let total = try balancesByUsage.values.reduce(OpalBase.Satoshi()) { partial, balances in
            let usageTotal = try balances.values.sumSatoshi(or: Error.paymentExceedsMaximumAmount)
            return try partial + usageTotal
        }
        
        return BalanceRefresh(balancesByUsage: balancesByUsage, total: total)
    }
}
