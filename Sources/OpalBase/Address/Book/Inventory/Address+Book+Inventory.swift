// Address+Book+Inventory.swift

import Foundation

extension Address.Book {
    struct Inventory {
        private var bucket: UsageBucket
        private var cacheValidityDurationValue: TimeInterval
        
        init(cacheValidityDuration: TimeInterval) {
            self.bucket = .init()
            self.cacheValidityDurationValue = cacheValidityDuration
        }
        
        var allEntries: [Entry] {
            bucket.allEntries
        }
        
        var cacheValidityDuration: TimeInterval {
            cacheValidityDurationValue
        }
        
        func isCacheValid(_ cache: Entry.Cache, currentDate: Date) -> Bool {
            cache.isValid(currentDate: currentDate, validityDuration: cacheValidityDurationValue)
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
        }
        
        mutating func updateEntry(at index: Int,
                                  usage: DerivationPath.Usage,
                                  _ update: (inout Entry) -> Void) {
            _ = bucket.updateEntry(at: index, usage: usage, update)
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
            try updateEntry(for: address) { entry in
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
                  let updatedEntry = bucket.updateEntry(at: location.index, usage: location.usage, update) else {
                throw Address.Book.Error.addressNotFound
            }
            
            return updatedEntry
        }
        
        private func locateEntry(for address: Address) -> (usage: DerivationPath.Usage, index: Int)? {
            bucket.locateEntry(for: address)
        }
    }
}

extension Address.Book.Inventory: Sendable {}

extension Address.Book {
    public func listEntries(for usage: DerivationPath.Usage) -> [Entry] {
        inventory.listEntries(for: usage)
    }
    
    func isCacheValid(_ cache: Entry.Cache, currentDate: Date) -> Bool {
        inventory.isCacheValid(cache, currentDate: currentDate)
    }
    
    public func updateCachedBalance(for address: Address,
                                    balance: Satoshi,
                                    timestamp: Date) throws {
        try inventory.updateCache(for: address,
                                  balance: balance,
                                  timestamp: timestamp)
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
