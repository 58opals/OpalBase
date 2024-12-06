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
