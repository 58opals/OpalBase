// Address+Book+Inventory~Operations.swift

import Foundation

extension Address.Book {
    public func listEntries(for usage: DerivationPath.Usage) -> [Entry] {
        inventory.listEntries(for: usage)
    }
    
    func checkCacheValidity(_ cache: Entry.Cache, currentDate: Date) -> Bool {
        inventory.checkCacheValidity(cache, currentDate: currentDate)
    }
    
    public func updateCachedBalance(for address: Address,
                                    balance: Satoshi,
                                    timestamp: Date) throws {
        try inventory.updateCache(for: address,
                                  balance: balance,
                                  timestamp: timestamp)
    }
    
    func updateCachedBalances(_ balances: [Address: Satoshi], timestamp: Date) throws {
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
    
    func countEntries(for usage: DerivationPath.Usage) -> Int {
        inventory.countEntries(for: usage)
    }
    
    func countUnusedEntries(for usage: DerivationPath.Usage) -> Int {
        inventory.countUnusedEntries(for: usage)
    }
    
    func readCacheValidityDuration() -> TimeInterval {
        inventory.cacheValidityDuration
    }
    
    func appendEntry(_ entry: Entry, usage: DerivationPath.Usage) {
        inventory.append(entry, usage: usage)
    }
    
    func findEntry(for address: Address) -> Entry? {
        inventory.findEntry(for: address)
    }
    
    func contains(address: Address) -> Bool {
        inventory.contains(address: address)
    }
    
    func listAllEntries() -> [Entry] {
        inventory.allEntries
    }
    
    func updateEntry(at index: Int,
                     usage: DerivationPath.Usage,
                     _ update: (inout Entry) -> Void) {
        inventory.updateEntry(at: index, usage: usage, update)
    }
    
    func markEntry(address: Address, isUsed: Bool) throws -> Entry {
        try inventory.mark(address: address, isUsed: isUsed)
    }
    
    func reserveEntry(address: Address) throws -> Entry {
        try inventory.reserve(address: address)
    }
    
    func releaseReservation(address: Address, shouldKeepUsed: Bool) throws -> Entry {
        try inventory.releaseReservation(address: address, shouldKeepUsed: shouldKeepUsed)
    }
}
