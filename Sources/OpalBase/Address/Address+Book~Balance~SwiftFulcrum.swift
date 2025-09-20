// Address+Book~Balance~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Address.Book {
    public func refreshBalances(using fulcrum: Fulcrum) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            try await refreshBalances(in: .receiving, fulcrum: fulcrum)
            try await refreshBalances(in: .change, fulcrum: fulcrum)
        }
        
        try await executeOrEnqueue(.refreshBalances, operation: operation)
    }
    
    private func refreshBalances(in usage: DerivationPath.Usage, fulcrum: Fulcrum) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            let entries = await listEntries(for: usage)
            let staleEntries = entries.filter { !$0.cache.isValid }
            
            try await withThrowingTaskGroup(of: (Address, Satoshi).self) { group in
                for entry in staleEntries {
                    group.addTask {
                        let balance = try await entry.address.fetchBalance(using: fulcrum)
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
    func fetchBalance(for address: Address, using fulcrum: Fulcrum) async throws -> Satoshi {
        let operation: @Sendable () async throws -> Satoshi = { [self] in
            let newBalance = try await address.fetchBalance(using: fulcrum)
            try await updateCache(for: address, with: newBalance)
            return newBalance
        }
        
        return try await executeOrEnqueue(.fetchBalance(address), operation: operation)
    }
}
