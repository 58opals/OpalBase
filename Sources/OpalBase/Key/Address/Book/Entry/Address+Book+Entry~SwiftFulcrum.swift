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
    static func combineHistories(receiving: [Transaction.Detailed], change: [Transaction.Detailed]) -> [Transaction.Detailed] {
        var uniqueTransactions: [Data: Transaction.Detailed] = .init()
        for transaction in receiving { uniqueTransactions[transaction.hash] = transaction }
        for transaction in change { uniqueTransactions[transaction.hash] = transaction }
        
        var mergedTransactions = Array(uniqueTransactions.values)
        mergedTransactions.sort {
            let lhsTime = ($0.blockTime ?? $0.time ?? UInt32.max)
            let rhsTime = ($1.blockTime ?? $1.time ?? UInt32.max)
            if lhsTime == rhsTime { return $0.hash.lexicographicallyPrecedes($1.hash) }
            return lhsTime < rhsTime
        }
        
        return mergedTransactions
    }
    
    public func fetchDetailedTransactions(for usage: DerivationPath.Usage,
                                          fromHeight: UInt? = nil,
                                          toHeight: UInt? = nil,
                                          includeUnconfirmed: Bool = true,
                                          using fulcrum: Fulcrum) async throws -> [Transaction.Detailed] {
        let operation: @Sendable () async throws -> [Transaction.Detailed] = { [self] in
            let entries = await getEntries(of: usage)
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
        
        return try await executeOrEnqueue(operation)
    }
    
    public func fetchCombinedHistory(fromHeight: UInt? = nil,
                                     toHeight: UInt? = nil,
                                     includeUnconfirmed: Bool = true,
                                     using fulcrum: Fulcrum) async throws -> [Transaction.Detailed] {
        let operation: @Sendable () async throws -> [Transaction.Detailed] = { [self] in
            async let receivingTransactions = fetchDetailedTransactions(for: .receiving,
                                                                        fromHeight: fromHeight,
                                                                        toHeight: toHeight,
                                                                        includeUnconfirmed: includeUnconfirmed,
                                                                        using: fulcrum)
            async let changeTransactions = fetchDetailedTransactions(for: .change,
                                                                     fromHeight: fromHeight,
                                                                     toHeight: toHeight,
                                                                     includeUnconfirmed: includeUnconfirmed,
                                                                     using: fulcrum)
            let (receivingTransactionHistory, changeTransactionHistory) = try await (receivingTransactions, changeTransactions)
            
            return Address.Book.combineHistories(receiving: receivingTransactionHistory, change: changeTransactionHistory)
        }
        
        return try await executeOrEnqueue(operation)
    }
    
    public func fetchCombinedHistoryPage(fromHeight: UInt? = nil,
                                         window: UInt,
                                         includeUnconfirmed: Bool = true,
                                         using fulcrum: Fulcrum) async throws -> Address.Book.Page<Transaction.Detailed> {
        let operation: @Sendable () async throws -> Address.Book.Page<Transaction.Detailed> = { [self] in
            let startHeight = fromHeight ?? 0
            let endHeight = (window == 0) ? nil : ((startHeight &+ window) &- 1)
            let transactions = try await self.fetchCombinedHistory(fromHeight: startHeight,
                                                                   toHeight: endHeight,
                                                                   includeUnconfirmed: includeUnconfirmed,
                                                                   using: fulcrum)
            let nextHeight = endHeight.map { $0 &+ 1 }
            
            return .init(transactions: transactions, nextFromHeight: nextHeight)
        }
        
        return try await executeOrEnqueue(operation)
    }
}

extension Address.Book {
    func refreshUsedStatus(fulcrum: Fulcrum) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            try await refreshUsedStatus(for: .receiving, fulcrum: fulcrum)
            try await refreshUsedStatus(for: .change, fulcrum: fulcrum)
        }
        
        try await executeOrEnqueue(operation)
    }
    
    func refreshUsedStatus(for usage: DerivationPath.Usage, fulcrum: Fulcrum) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            let entries = await getEntries(of: usage)
            
            for entry in entries {
                if entry.isUsed { continue }
                
                if let cacheBalance = entry.cache.balance {
                    if cacheBalance.uint64 > 0 {
                        let utxos = try await entry.address.fetchUnspentTransactionOutputs(fulcrum: fulcrum)
                        if !utxos.isEmpty {
                            try await mark(address: entry.address, isUsed: true)
                        }
                    } else if cacheBalance.uint64 == 0 {
                        let transactionHistory = try await entry.address.fetchSimpleTransactionHistory(fulcrum: fulcrum)
                        if !transactionHistory.isEmpty {
                            try await mark(address: entry.address, isUsed: true)
                        }
                    }
                }
            }
        }
        
        try await executeOrEnqueue(operation)
    }
}

extension Address.Book {
    public func updateAddressUsageStatus(using fulcrum: Fulcrum) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.updateAddressUsageStatus(for: .receiving, using: fulcrum) }
                group.addTask { try await self.updateAddressUsageStatus(for: .change, using: fulcrum) }
                try await group.waitForAll()
            }
        }
        
        try await executeOrEnqueue(operation)
    }
    
    private func updateAddressUsageStatus(for usage: DerivationPath.Usage, using fulcrum: Fulcrum) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            let entries = await getEntries(of: usage)
            
            try await withThrowingTaskGroup(of: (Address, Bool).self) { group in
                for entry in entries where !entry.isUsed {
                    group.addTask {
                        let isActuallyUsed = try await self.checkIfUsed(entry: entry, using: fulcrum)
                        return (entry.address, isActuallyUsed)
                    }
                }
                
                for try await (address, isUsed) in group {
                    if isUsed { try await self.mark(address: address, isUsed: true) }
                }
            }
        }
        
        try await executeOrEnqueue(operation)
    }
    
    private func checkIfUsed(entry: Entry, using fulcrum: Fulcrum) async throws -> Bool {
        let operation: @Sendable () async throws -> Bool = {
            if let cacheBalance = entry.cache.balance, cacheBalance.uint64 > 0 { return true }
            
            let utxos = try await entry.address.fetchUnspentTransactionOutputs(fulcrum: fulcrum)
            if !utxos.isEmpty { return true }
            
            let txHistory = try await entry.address.fetchSimpleTransactionHistory(fulcrum: fulcrum)
            return !txHistory.isEmpty
        }
        
        return try await executeOrEnqueue(operation)
    }
}

extension Address.Book {
    private func countUsedEntries() -> Int {
        getUsedEntries(for: .receiving).count + getUsedEntries(for: .change).count
    }
    
    func scanForUsedAddresses(using fulcrum: Fulcrum) async throws {
        let operation: @Sendable () async throws -> Void = { [self] in
            var previousUsedCount = await countUsedEntries()
            
            repeat {
                try await updateAddressUsageStatus(using: fulcrum)
                let currentUsedCount = await countUsedEntries()
                if currentUsedCount == previousUsedCount { break }
                previousUsedCount = currentUsedCount
            } while true
        }
        
        try await executeOrEnqueue(operation)
    }
}

extension Address.Book.Entry {
    public func subscribe(fulcrum: Fulcrum) async throws -> (requestedID: UUID,
                                                             subscriptionID: String,
                                                             initialStatus: String,
                                                             followingStatus: AsyncThrowingStream<Response.Result.Blockchain.Address.SubscribeNotification, Swift.Error>,
                                                             cancel: () async -> Void) {
        return try await self.address.subscribe(fulcrum: fulcrum)
    }
}
