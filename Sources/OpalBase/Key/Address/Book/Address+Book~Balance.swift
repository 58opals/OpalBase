// Address+Book~Balance.swift

import Foundation

extension Address.Book {
    func getTotalBalanceFromCache() throws -> Satoshi {
        let allEntries = receivingEntries + changeEntries
        let allBalances = allEntries.map { $0.cache.balance }
        let totalBalance = allBalances.map({$0?.uint64 ?? 0}).reduce(0, +)
        return try Satoshi(totalBalance)
    }
    
    func getBalanceFromCache(address: Address) throws -> Satoshi? {
        guard let entry = findEntry(for: address) else { throw Error.entryNotFound }
        
        return entry.cache.balance
    }
}
