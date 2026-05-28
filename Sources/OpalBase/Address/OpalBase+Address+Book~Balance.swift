// OpalBase+Address+Book~Balance.swift

import Foundation

extension _OpalBase.Address.Book {
    func calculateCachedTotalBalance() throws -> OpalBase.Satoshi {
        let allEntries = listAllEntries()
        let validBalances = allEntries.compactMap { entry -> OpalBase.Satoshi? in
            guard let balance = entry.cache.balance,
                  isCacheValid(entry.cache, currentDate: .now) else {
                return nil
            }
            return balance
        }
        
        return try validBalances.sumSatoshi()
    }
    
    func readCachedBalance(for address: OpalBase.Address) throws -> OpalBase.Satoshi? {
        guard let entry = findEntry(for: address) else { throw Error.entryNotFound }
        
        guard isCacheValid(entry.cache, currentDate: .now) else { return nil }
        guard let balance = entry.cache.balance else { return nil }
        
        return balance
    }
}

extension _OpalBase.Address.Book {
    func calculateTotalUnspentBalance() throws -> OpalBase.Satoshi {
        let utxos = utxoStore.listUTXOs()
        return try utxos.sumSatoshi { try OpalBase.Satoshi($0.value) }
    }
}
