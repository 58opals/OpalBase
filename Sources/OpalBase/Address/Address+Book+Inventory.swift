// Address+Book+Inventory.swift

import Foundation

extension Address.Book {
    struct Inventory {
        private var bucket: UsageBucket
        private var addressIndex: [Address: (usage: DerivationPath.Usage, index: Int)]
        private var cacheValidityDurationValue: TimeInterval
        
        init(cacheValidityDuration: TimeInterval) {
            self.bucket = .init()
            self.addressIndex = .init()
            self.cacheValidityDurationValue = cacheValidityDuration
        }
        
        var allEntries: [Entry] {
            bucket.allEntries
        }
        
        var cacheValidityDuration: TimeInterval {
            cacheValidityDurationValue
        }
        
        func checkCacheValidity(_ cache: Entry.Cache, currentDate: Date) -> Bool {
            cache.checkValidity(currentDate: currentDate, validityDuration: cacheValidityDurationValue)
        }
        
        func listEntries(for usage: DerivationPath.Usage) -> [Entry] {
            bucket.fetchEntries(for: usage)
        }
        
        func countEntries(for usage: DerivationPath.Usage) -> Int {
            bucket.countEntries(for: usage)
        }
        
        func listUsedEntries(for usage: DerivationPath.Usage) -> Set<Entry> {
            Set(listEntries(for: usage).filter { $0.isUsed })
        }
        
        func countUnusedEntries(for usage: DerivationPath.Usage) -> Int {
            bucket.countUnusedEntries(for: usage)
        }
        
        func calculateNextIndex(for usage: DerivationPath.Usage) -> UInt32 {
            UInt32(bucket.countEntries(for: usage))
        }
        
        func contains(address: Address) -> Bool {
            locateEntry(for: address) != nil
        }
        
        func findEntry(for address: Address) -> Entry? {
            guard let location = locateEntry(for: address) else { return nil }
            return bucket.fetchEntry(at: location.index, usage: location.usage)
        }
        
        mutating func append(_ entry: Entry, usage: DerivationPath.Usage) {
            bucket.appendEntry(entry, usage: usage)
            let newIndex = bucket.countEntries(for: usage) - 1
            recordAddressIndex(for: entry, usage: usage, index: newIndex)
        }
        
        mutating func updateEntry(at index: Int,
                                  usage: DerivationPath.Usage,
                                  _ update: (inout Entry) -> Void) {
            _ = updateEntryAndIndex(at: index, usage: usage, update)
        }
        
        mutating func updateCacheValidityDuration(to newDuration: TimeInterval) {
            cacheValidityDurationValue = newDuration
        }
        
        mutating func updateCache(for address: Address,
                                  balance: Satoshi,
                                  timestamp: Date) throws {
            _ = try updateEntry(for: address) { entry in
                entry.cache = Entry.Cache(balance: balance,
                                          lastUpdated: timestamp)
            }
        }
        
        mutating func mark(address: Address, isUsed: Bool) throws -> Entry {
            try updateEntry(for: address) { entry in
                entry.isUsed = isUsed
                entry.isReserved = false
            }
        }
        
        mutating func reserve(address: Address) throws -> Entry {
            guard let currentEntry = findEntry(for: address) else { throw Address.Book.Error.addressNotFound }
            guard !currentEntry.isReserved else { throw Address.Book.Error.entryAlreadyReserved(currentEntry) }
            
            return try updateEntry(for: address) { entry in
                entry.isUsed = true
                entry.isReserved = true
            }
        }
        
        mutating func releaseReservation(address: Address, shouldKeepUsed: Bool) throws -> Entry {
            try updateEntry(for: address) { entry in
                entry.isUsed = shouldKeepUsed
                entry.isReserved = false
            }
        }
        
        private mutating func updateEntry(for address: Address,
                                          _ update: (inout Entry) -> Void) throws -> Entry {
            guard let location = locateEntry(for: address),
                  let updatedEntry = updateEntryAndIndex(at: location.index,
                                                         usage: location.usage,
                                                         update) else {
                throw Address.Book.Error.addressNotFound
            }
            
            return updatedEntry
        }
        
        private func locateEntry(for address: Address) -> (usage: DerivationPath.Usage, index: Int)? {
            addressIndex[address]
        }
        
        private mutating func updateEntryAndIndex(at index: Int,
                                                  usage: DerivationPath.Usage,
                                                  _ update: (inout Entry) -> Void) -> Entry? {
            guard let existingEntry = bucket.fetchEntry(at: index, usage: usage),
                  let updatedEntry = bucket.updateEntry(at: index, usage: usage, update) else {
                return nil
            }
            
            refreshAddressIndex(oldEntry: existingEntry,
                                updatedEntry: updatedEntry,
                                usage: usage,
                                index: index)
            return updatedEntry
        }
        
        private mutating func recordAddressIndex(for entry: Entry,
                                                 usage: DerivationPath.Usage,
                                                 index: Int) {
            if let location = addressIndex[entry.address] {
                switch (location.usage, usage) {
                case (.receiving, _):
                    return
                case (.change, .receiving):
                    addressIndex[entry.address] = (usage, index)
                case (.change, .change):
                    return
                }
            } else {
                addressIndex[entry.address] = (usage, index)
            }
        }
        
        private mutating func refreshAddressIndex(oldEntry: Entry,
                                                  updatedEntry: Entry,
                                                  usage: DerivationPath.Usage,
                                                  index: Int) {
            if oldEntry.address == updatedEntry.address {
                recordAddressIndex(for: updatedEntry, usage: usage, index: index)
                return
            }
            
            removeAddressIndex(for: oldEntry, usage: usage, index: index)
            recordAddressIndex(for: updatedEntry, usage: usage, index: index)
        }
        
        private mutating func removeAddressIndex(for entry: Entry,
                                                 usage: DerivationPath.Usage,
                                                 index: Int) {
            guard let location = addressIndex[entry.address],
                  location.usage == usage,
                  location.index == index else {
                return
            }
            addressIndex[entry.address] = nil
        }
    }
}

extension Address.Book.Inventory: Sendable {}

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
