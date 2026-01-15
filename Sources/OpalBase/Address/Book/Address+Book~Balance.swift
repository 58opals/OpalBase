// Address+Book~Balance.swift

import Foundation

extension Address.Book {
    func calculateCachedTotalBalance() throws -> Satoshi {
        let allEntries = listAllEntries()
        let validBalances = allEntries.compactMap { entry -> Satoshi? in
            guard let balance = entry.cache.balance,
                  checkCacheValidity(entry.cache, currentDate: .now) else {
                return nil
            }
            return balance
        }
        
        var aggregate: Satoshi = .init()
        for balance in validBalances {
            aggregate = try aggregate + balance
        }
        
        return aggregate
    }
    
    func readCachedBalance(for address: Address) throws -> Satoshi? {
        guard let entry = findEntry(for: address) else { throw Error.entryNotFound }
        
        guard checkCacheValidity(entry.cache, currentDate: .now) else { return nil }
        guard let balance = entry.cache.balance else { return nil }
        
        return balance
    }
}

extension Address.Book {
    func calculateTotalUnspentBalance() throws -> Satoshi {
        let utxos = utxoStore.listUTXOs()
        var total: Satoshi = .init()
        
        for unspent in utxos {
            total = try total + Satoshi(unspent.value)
        }
        
        return total
    }
}
