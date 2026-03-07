// OpalBase.Address+BookActor~Operations.swift

import Foundation

extension _OpalBase.Address.Book {
    public func listEntries(for usage: OpalBase.DerivationPath.UsageModel) -> [EntryModel] {
        inventory.listEntries(for: usage)
    }
    
    func checkCacheValidity(_ cache: EntryModel.Cache, currentDate: Date) -> Bool {
        inventory.checkCacheValidity(cache, currentDate: currentDate)
    }
    
    public func updateCachedBalance(for address: OpalBase.Address,
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
    
    func countEntries(for usage: OpalBase.DerivationPath.UsageModel) -> Int {
        inventory.countEntries(for: usage)
    }
    
    func countUnusedEntries(for usage: OpalBase.DerivationPath.UsageModel) -> Int {
        inventory.countUnusedEntries(for: usage)
    }
    
    func readCacheValidityDuration() -> TimeInterval {
        inventory.cacheValidityDuration
    }
    
    func appendEntry(_ entry: EntryModel, usage: OpalBase.DerivationPath.UsageModel) {
        inventory.append(entry, usage: usage)
    }
    
    func findEntry(for address: OpalBase.Address) -> EntryModel? {
        inventory.findEntry(for: address)
    }
    
    func contains(address: OpalBase.Address) -> Bool {
        inventory.contains(address: address)
    }
    
    func listAllEntries() -> [EntryModel] {
        inventory.allEntries
    }
    
    func updateEntry(at index: Int,
                     usage: OpalBase.DerivationPath.UsageModel,
                     _ update: (inout EntryModel) -> Void) {
        inventory.updateEntry(at: index, usage: usage, update)
    }
    
    func markEntry(address: OpalBase.Address, isUsed: Bool) throws -> EntryModel {
        try inventory.mark(address: address, isUsed: isUsed)
    }
    
    func reserveEntry(address: OpalBase.Address) throws -> EntryModel {
        try inventory.reserve(address: address)
    }
    
    func releaseReservation(address: OpalBase.Address, shouldKeepUsed: Bool) throws -> EntryModel {
        try inventory.releaseReservation(address: address, shouldKeepUsed: shouldKeepUsed)
    }
}

