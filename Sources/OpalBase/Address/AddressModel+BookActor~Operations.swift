// AddressModel+BookActor+InventoryModel~OperationsModel.swift

import Foundation

extension AddressModel.BookActor {
    public func listEntries(for usage: DerivationPathModel.UsageModel) -> [EntryModel] {
        inventory.listEntries(for: usage)
    }
    
    func checkCacheValidity(_ cache: EntryModel.Cache, currentDate: Date) -> Bool {
        inventory.checkCacheValidity(cache, currentDate: currentDate)
    }
    
    public func updateCachedBalance(for address: AddressModel,
                                    balance: SatoshiModel,
                                    timestamp: Date) throws {
        try inventory.updateCache(for: address,
                                  balance: balance,
                                  timestamp: timestamp)
    }
    
    func updateCachedBalances(_ balances: [AddressModel: SatoshiModel], timestamp: Date) throws {
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
    
    func countEntries(for usage: DerivationPathModel.UsageModel) -> Int {
        inventory.countEntries(for: usage)
    }
    
    func countUnusedEntries(for usage: DerivationPathModel.UsageModel) -> Int {
        inventory.countUnusedEntries(for: usage)
    }
    
    func readCacheValidityDuration() -> TimeInterval {
        inventory.cacheValidityDuration
    }
    
    func appendEntry(_ entry: EntryModel, usage: DerivationPathModel.UsageModel) {
        inventory.append(entry, usage: usage)
    }
    
    func findEntry(for address: AddressModel) -> EntryModel? {
        inventory.findEntry(for: address)
    }
    
    func contains(address: AddressModel) -> Bool {
        inventory.contains(address: address)
    }
    
    func listAllEntries() -> [EntryModel] {
        inventory.allEntries
    }
    
    func updateEntry(at index: Int,
                     usage: DerivationPathModel.UsageModel,
                     _ update: (inout EntryModel) -> Void) {
        inventory.updateEntry(at: index, usage: usage, update)
    }
    
    func markEntry(address: AddressModel, isUsed: Bool) throws -> EntryModel {
        try inventory.mark(address: address, isUsed: isUsed)
    }
    
    func reserveEntry(address: AddressModel) throws -> EntryModel {
        try inventory.reserve(address: address)
    }
    
    func releaseReservation(address: AddressModel, shouldKeepUsed: Bool) throws -> EntryModel {
        try inventory.releaseReservation(address: address, shouldKeepUsed: shouldKeepUsed)
    }
}
