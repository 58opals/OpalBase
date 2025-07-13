// Address+Book~Balance~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Address.Book {
    public func refreshBalances(using fulcrum: Fulcrum) async throws {
        try await refreshBalances(in: receivingEntries, fulcrum: fulcrum)
        try await refreshBalances(in: changeEntries, fulcrum: fulcrum)
    }
    
    private func refreshBalances(in entries: [Entry], fulcrum: Fulcrum) async throws {
        let staleEntries = entries.filter { !$0.cache.isValid }
        
        try await withThrowingTaskGroup(of: (Address, Satoshi).self) { group in
            for entry in staleEntries {
                group.addTask {
                    let balance = try await entry.address.fetchBalance(using: fulcrum)
                    return (entry.address, balance)
                }
            }
            
            for try await (address, balance) in group {
                try updateCache(for: address, with: balance)
            }
        }
    }
}

extension Address.Book {
    func getBalanceFromBlockchain(address: Address, fulcrum: Fulcrum) async throws -> Satoshi {
        let newBalance = try await address.fetchBalance(using: fulcrum)
        try updateCache(for: address, with: newBalance)
        return newBalance
    }
}
