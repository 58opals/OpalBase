// Address+Book~Balance.swift

import Foundation

extension Address.Book {
    func calculateCachedTotalBalance() throws -> Satoshi {
        let allEntries = inventory.allEntries
        let allBalances = allEntries.map { $0.cache.balance }
        let totalBalance = allBalances.map({$0?.uint64 ?? 0}).reduce(0, +)
        return try Satoshi(totalBalance)
    }
    
    func readCachedBalance(for address: Address) throws -> Satoshi? {
        guard let entry = inventory.findEntry(for: address) else { throw Error.entryNotFound }
        
        return entry.cache.balance
    }
}
