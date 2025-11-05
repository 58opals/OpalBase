// Address+Book~Balance.swift

import Foundation

extension Address.Book {
    func calculateCachedTotalBalance() throws -> Satoshi {
        let allEntries = listAllEntries()
        let allBalances = allEntries.map { $0.cache.balance?.uint64 ?? 0 }
        
        var aggregate: UInt64 = 0
        for balance in allBalances {
            let (updated, didOverflow) = aggregate.addingReportingOverflow(balance)
            if didOverflow { throw Satoshi.Error.exceedsMaximumAmount }
            aggregate = updated
        }
        
        return try Satoshi(aggregate)
    }
    
    func readCachedBalance(for address: Address) throws -> Satoshi? {
        guard let entry = findEntry(for: address) else { throw Error.entryNotFound }
        
        return entry.cache.balance
    }
}
