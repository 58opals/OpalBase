// Address+Book~Balance.swift

import Foundation

extension Address.Book {
    func calculateCachedTotalBalance() throws -> Satoshi {
        let allEntries = listAllEntries()
        let validBalances = allEntries.compactMap { entry -> UInt64? in
            guard let balance = entry.cache.balance,
                  isCacheValid(entry.cache, currentDate: .now) else {
                return nil
            }
            return balance.uint64
        }
        
        var aggregate: UInt64 = 0
        for balance in validBalances {
            let (updated, didOverflow) = aggregate.addingReportingOverflow(balance)
            if didOverflow { throw Satoshi.Error.exceedsMaximumAmount }
            aggregate = updated
        }
        
        return try Satoshi(aggregate)
    }
    
    func readCachedBalance(for address: Address) throws -> Satoshi? {
        guard let entry = findEntry(for: address) else { throw Error.entryNotFound }
        
        guard isCacheValid(entry.cache, currentDate: .now) else { return nil }
        guard let balance = entry.cache.balance else { return nil }
        
        return balance
    }
}

extension Address.Book {
    func calculateTotalUnspentBalance() -> Satoshi {
        let utxos = utxoStore.listUTXOs()
        var aggregateValue: UInt64 = 0
        
        for unspent in utxos {
            let (updatedValue, didOverflow) = aggregateValue.addingReportingOverflow(unspent.value)
            precondition(!didOverflow, "Total unspent balance exceeds representable range")
            aggregateValue = updatedValue
        }
        
        guard let balance = try? Satoshi(aggregateValue) else {
            preconditionFailure("Total unspent balance exceeds supported maximum")
        }
        
        return balance
    }
}
