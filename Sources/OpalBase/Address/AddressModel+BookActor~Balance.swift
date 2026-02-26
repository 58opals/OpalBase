// AddressModel+BookActor~Balance.swift

import Foundation

extension AddressModel.BookActor {
    func calculateCachedTotalBalance() throws -> SatoshiModel {
        let allEntries = listAllEntries()
        let validBalances = allEntries.compactMap { entry -> SatoshiModel? in
            guard let balance = entry.cache.balance,
                  checkCacheValidity(entry.cache, currentDate: .now) else {
                return nil
            }
            return balance
        }
        
        return try validBalances.sumSatoshi()
    }
    
    func readCachedBalance(for address: AddressModel) throws -> SatoshiModel? {
        guard let entry = findEntry(for: address) else { throw Error.entryNotFound }
        
        guard checkCacheValidity(entry.cache, currentDate: .now) else { return nil }
        guard let balance = entry.cache.balance else { return nil }
        
        return balance
    }
}

extension AddressModel.BookActor {
    func calculateTotalUnspentBalance() throws -> SatoshiModel {
        let utxos = utxoStore.listUTXOs()
        return try utxos.sumSatoshi { try SatoshiModel($0.value) }
    }
}
