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
        let targetUsages = DerivationPath.Usage.targets(for: usage)
        var balancesByUsage: [DerivationPath.Usage: [Address: Satoshi]] = .init()
        
        for currentUsage in targetUsages {
            let entries = await addressBook.listEntries(for: currentUsage)
            
            guard !entries.isEmpty else {
                balancesByUsage[currentUsage] = .init()
                continue
            }
            
            let addresses = entries.map(\.address)
            let usageResults = try await addresses.mapConcurrently(limit: Concurrency.Tuning.maximumConcurrentNetworkRequests) { address in
                do {
                    let balance = try await loader(address)
                    return (address, balance)
                } catch {
                    throw Error.balanceRefreshFailed(address, error)
                }
            }
            
            var usageBalances: [Address: Satoshi] = .init()
            let refreshTimestamp = Date()
            for (address, balance) in usageResults {
                usageBalances[address] = balance
                do {
                    try await addressBook.updateCachedBalance(for: address,
                                                              balance: balance,
                                                              timestamp: refreshTimestamp)
                } catch {
                    throw Error.balanceRefreshFailed(address, error)
                }
            }
            balancesByUsage[currentUsage] = usageBalances
        }
        
        var total = try Satoshi(0)
        for usageBalances in balancesByUsage.values {
            for balance in usageBalances.values {
                do {
                    total = try total + balance
                } catch {
                    throw Error.paymentExceedsMaximumAmount
                }
            }
        }
        
        return BalanceRefresh(balancesByUsage: balancesByUsage, total: total)
    }
}
