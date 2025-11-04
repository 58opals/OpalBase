// Account~Command~Balance.swift

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
        let targetUsages = usage.map { [$0] } ?? DerivationPath.Usage.allCases
        var balancesByUsage: [DerivationPath.Usage: [Address: Satoshi]] = .init()
        
        for currentUsage in targetUsages {
            let entries = await addressBook.listEntries(for: currentUsage)
            
            guard !entries.isEmpty else {
                balancesByUsage[currentUsage] = .init()
                continue
            }
            
            var usageBalances: [Address: Satoshi] = .init()
            try await withThrowingTaskGroup(of: (Address, Satoshi, Date).self) { group in
                for entry in entries {
                    group.addTask {
                        let balance: Satoshi
                        do {
                            balance = try await loader(entry.address)
                        } catch {
                            throw Error.balanceRefreshFailed(entry.address, error)
                        }
                        return (entry.address, balance, Date())
                    }
                }
                
                for try await (address, balance, timestamp) in group {
                    usageBalances[address] = balance
                    do {
                        try await addressBook.updateCachedBalance(for: address,
                                                                  balance: balance,
                                                                  timestamp: timestamp)
                    } catch {
                        throw Error.balanceRefreshFailed(address, error)
                    }
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
