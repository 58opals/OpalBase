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
        
        return try validBalances.sumSatoshi()
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
        return try utxos.sumSatoshi { try Satoshi($0.value) }
    }
}
