// Address+Book~Balance~WalletNode.swift

import Foundation

extension Address.Book {
    public func refreshBalances(using node: Network.Wallet.Node) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            try await refreshBalances(in: .receiving, node: node)
            try await refreshBalances(in: .change, node: node)
        }
        
        try await executeOrEnqueue(.refreshBalances, operation: operation)
    }
    
    private func refreshBalances(in usage: DerivationPath.Usage, node: Network.Wallet.Node) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            let entries = await listEntries(for: usage)
            let staleEntries = entries.filter { !$0.cache.isValid }
            
            try await withThrowingTaskGroup(of: (Address, Satoshi).self) { group in
                for entry in staleEntries {
                    group.addTask {
                        let balance = try await node.balance(for: entry.address, includeUnconfirmed: true)
                        return (entry.address, balance)
                    }
                }
                
                for try await (address, balance) in group {
                    try await updateCache(for: address, with: balance)
                }
            }
        }
        
        let scope = Request.Scope(usage: usage)
        try await executeOrEnqueue(.refreshBalancesSubset(scope), operation: operation)
    }
}

extension Address.Book {
    func fetchBalance(for address: Address, using node: Network.Wallet.Node) async throws -> Satoshi {
        let operation: @Sendable () async throws -> Satoshi = { [self] in
            let newBalance = try await node.balance(for: address, includeUnconfirmed: true)
            try await updateCache(for: address, with: newBalance)
            return newBalance
        }
        
        return try await executeOrEnqueue(.fetchBalance(address), operation: operation)
    }
}
