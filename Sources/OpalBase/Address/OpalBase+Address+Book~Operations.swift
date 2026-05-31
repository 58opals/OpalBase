// OpalBase+Address+Book~Operations.swift

import Foundation

extension _OpalBase.Address.Book {
    func listEntries(for usage: OpalBase.Key.DerivationPath.Usage) -> [Entry] {
        inventory.listEntries(for: usage)
    }
    
    func isCacheValid(_ cache: Entry.Cache, currentDate: Date) -> Bool {
        inventory.isCacheValid(cache, currentDate: currentDate)
    }
    
    func updateCachedBalance(for address: OpalBase.Address,
                                    balance: OpalBase.Satoshi,
                                    timestamp: Date) throws {
        try inventory.updateCache(for: address,
                                  balance: balance,
                                  timestamp: timestamp)
    }
    
    func updateCachedBalances(_ balances: [OpalBase.Address: OpalBase.Satoshi], timestamp: Date) throws {
        for (address, balance) in balances {
            do {
                try inventory.updateCache(for: address,
                                          balance: balance,
                                          timestamp: timestamp)
            } catch {
                throw Error.cacheUpdateFailed(address, error)
            }
        }
    }
    
    func countEntries(for usage: OpalBase.Key.DerivationPath.Usage) -> Int {
        inventory.countEntries(for: usage)
    }
    
    func countUnusedEntries(for usage: OpalBase.Key.DerivationPath.Usage) -> Int {
        inventory.countUnusedEntries(for: usage)
    }

    func findEntry(for address: OpalBase.Address) -> Entry? {
        inventory.findEntry(for: address)
    }
    
    func contains(address: OpalBase.Address) -> Bool {
        inventory.contains(address: address)
    }
    
    func listAllEntries() -> [Entry] {
        inventory.allEntries
    }

    func reserveEntry(address: OpalBase.Address) throws -> Entry {
        try inventory.reserve(address: address)
    }
    
    func releaseReservation(address: OpalBase.Address, shouldKeepUsed: Bool) throws -> Entry {
        try inventory.releaseReservation(address: address, shouldKeepUsed: shouldKeepUsed)
    }
}
