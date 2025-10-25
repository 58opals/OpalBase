// Address+Book~Balance~FulcrumService.swift

import Foundation

extension Address.Book {
    public func refreshBalances(using service: Network.FulcrumService) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            try await refreshBalances(in: .receiving, service: service)
            try await refreshBalances(in: .change, service: service)
        }
        
        try await executeOrEnqueue(.refreshBalances, operation: operation)
    }
    
    private func refreshBalances(in usage: DerivationPath.Usage, service: Network.FulcrumService) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            let entries = await listEntries(for: usage)
            let staleEntries = entries.filter { !$0.cache.isValid }
            
            try await withThrowingTaskGroup(of: (Address, Satoshi).self) { group in
                for entry in staleEntries {
                    group.addTask {
                        let balance = try await service.balance(for: entry.address, includeUnconfirmed: true)
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
    func fetchBalance(for address: Address, using service: Network.FulcrumService) async throws -> Satoshi {
        let operation: @Sendable () async throws -> Satoshi = { [self] in
            let newBalance = try await service.balance(for: address, includeUnconfirmed: true)
            try await updateCache(for: address, with: newBalance)
            return newBalance
        }
        
        return try await executeOrEnqueue(.fetchBalance(address), operation: operation)
    }
}
