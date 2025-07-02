// Address+Book+Entry~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Address.Book.Entry {
    mutating func fetchBalance(using fulcrum: Fulcrum) async throws {
        let balance = try await address.fetchBalance(using: fulcrum)
        self.cache = .init(balance: balance)
    }
    
    mutating func getBalance(using fulcrum: Fulcrum) async throws -> Satoshi {
        if cache.isValid, let cacheBalance = cache.balance {
            return cacheBalance
        } else {
            try await fetchBalance(using: fulcrum)
            guard cache.isValid else { throw Address.Book.Error.cacheInvalid }
            guard let fetchedBalance = cache.balance else { throw Address.Book.Error.cacheUpdateFailed }
            return fetchedBalance
        }
    }
}

extension Address.Book.Entry {
    func fetchSimpleTransactions(fromHeight: UInt? = nil,
                                 toHeight: UInt? = nil,
                                 includeUnconfirmed: Bool = true,
                                 fulcrum: Fulcrum) async throws -> [Transaction.Simple] {
        let simpleTransactions = try await address.fetchSimpleTransactionHistory(fromHeight: fromHeight,
                                                                                 toHeight: toHeight,
                                                                                 includeUnconfirmed: includeUnconfirmed,
                                                                                 fulcrum: fulcrum)
        
        return simpleTransactions
    }
    
    func fetchFullTransactions(fromHeight: UInt? = nil,
                               toHeight: UInt? = nil,
                               includeUnconfirmed: Bool = true,
                               fulcrum: Fulcrum) async throws -> [Transaction.Detailed] {
        let simpleTransactions = try await self.fetchSimpleTransactions(fromHeight: fromHeight,
                                                                        toHeight: toHeight,
                                                                        includeUnconfirmed: includeUnconfirmed,
                                                                        fulcrum: fulcrum)
        let transactionHashes = simpleTransactions.map { $0.transactionHash }
        
        let detailedTransactions = try await withThrowingTaskGroup(of: Transaction.Detailed.self) { group in
            for transactionHash in transactionHashes {
                group.addTask {
                    try await Transaction.fetchFullTransaction(for: transactionHash.originalData, using: fulcrum)
                }
            }
            
            var detailedTransactions: [Transaction.Detailed] = .init()
            for try await transaction in group {
                detailedTransactions.append(transaction)
            }
            
            return detailedTransactions
        }
        
        return detailedTransactions
    }
}

extension Address.Book {
    public func fetchDetailedTransactions(for usage: DerivationPath.Usage,
                                          fromHeight: UInt? = nil,
                                          toHeight: UInt? = nil,
                                          includeUnconfirmed: Bool = true,
                                          using fulcrum: Fulcrum) async throws -> [Transaction.Detailed] {
        let entries = getEntries(of: usage)
        var allDetailedTransactions: [Transaction.Detailed] = []
        allDetailedTransactions.reserveCapacity(entries.count * 10)
        
        try await withThrowingTaskGroup(of: [Transaction.Detailed].self) { group in
            for entry in entries {
                group.addTask {
                    try await entry.fetchFullTransactions(fromHeight: fromHeight,
                                                          toHeight: toHeight,
                                                          includeUnconfirmed: includeUnconfirmed,
                                                          fulcrum: fulcrum)
                }
            }
            
            for try await detailedList in group {
                allDetailedTransactions.append(contentsOf: detailedList)
            }
        }
        
        return allDetailedTransactions
    }
}

extension Address.Book {
    public func refreshUsedStatus(fulcrum: Fulcrum) async throws {
        try await refreshUsedStatus(for: .receiving, fulcrum: fulcrum)
        try await refreshUsedStatus(for: .change, fulcrum: fulcrum)
    }
    
    func refreshUsedStatus(for usage: DerivationPath.Usage, fulcrum: Fulcrum) async throws {
        let entries = getEntries(of: usage)
        
        for entry in entries {
            if entry.isUsed { continue }
            
            if let cacheBalance = entry.cache.balance {
                if cacheBalance.uint64 > 0 {
                    let unspentTransactionOutputs = try await entry.address.fetchUnspentTransactionOutputs(fulcrum: fulcrum)
                    if !unspentTransactionOutputs.isEmpty {
                        try mark(address: entry.address, isUsed: true)
                    }
                } else if cacheBalance.uint64 == 0 {
                    let transactionHistory = try await entry.address.fetchSimpleTransactionHistory(fulcrum: fulcrum)
                    if !transactionHistory.isEmpty {
                        try mark(address: entry.address, isUsed: true)
                    }
                }
            }
        }
    }
}

extension Address.Book {
    public func updateAddressUsageStatus(using fulcrum: Fulcrum) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.updateAddressUsageStatus(for: .receiving, using: fulcrum) }
            group.addTask { try await self.updateAddressUsageStatus(for: .change, using: fulcrum) }
            try await group.waitForAll()
        }
    }
    
    private func updateAddressUsageStatus(for usage: DerivationPath.Usage, using fulcrum: Fulcrum) async throws {
        let entries = getEntries(of: usage)
        
        try await withThrowingTaskGroup(of: (Address, Bool).self) { group in
            for entry in entries where !entry.isUsed {
                group.addTask {
                    let isActuallyUsed = try await self.checkIfUsed(entry: entry, using: fulcrum)
                    return (entry.address, isActuallyUsed)
                }
            }
            
            for try await (address, isUsed) in group {
                if isUsed { try self.mark(address: address, isUsed: true) }
            }
        }
    }
    
    private func checkIfUsed(entry: Entry, using fulcrum: Fulcrum) async throws -> Bool {
        if let cacheBalance = entry.cache.balance, cacheBalance.uint64 > 0 {
            let utxos = try await entry.address.fetchUnspentTransactionOutputs(fulcrum: fulcrum)
            if !utxos.isEmpty { return true }
        } else {
            let txHistory = try await entry.address.fetchSimpleTransactionHistory(fulcrum: fulcrum)
            if !txHistory.isEmpty { return true }
        }
        return false
    }
}
