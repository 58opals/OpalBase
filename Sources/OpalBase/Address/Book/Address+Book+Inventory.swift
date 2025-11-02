// Address+Book+Inventory.swift

import Foundation

extension Address.Book {
    public struct Inventory {
        private var entriesByUsage: [DerivationPath.Usage: [Entry]]
        private var cacheValidityDurationValue: TimeInterval
        
        init(cacheValidityDuration: TimeInterval) {
            self.entriesByUsage = .init(uniqueKeysWithValues: DerivationPath.Usage.allCases.map { usage in (usage, .init()) } )
            self.cacheValidityDurationValue = cacheValidityDuration
        }
        
        var allEntries: [Entry] {
            DerivationPath.Usage.allCases.flatMap { entriesByUsage[$0, default: .init()] }
        }
        
        var cacheValidityDuration: TimeInterval {
            cacheValidityDurationValue
        }
        
        func listEntries(for usage: DerivationPath.Usage) -> [Entry] {
            entriesByUsage[usage, default: .init()]
        }
        
        func countEntries(for usage: DerivationPath.Usage) -> Int {
            listEntries(for: usage).count
        }
        
        func listUsedEntries(for usage: DerivationPath.Usage) -> Set<Entry> {
            Set(listEntries(for: usage).filter { $0.isUsed })
        }
        
        func countUnusedEntries(for usage: DerivationPath.Usage) -> Int {
            listEntries(for: usage).reduce(into: 0) { result, entry in
                if !entry.isUsed {
                    result += 1
                }
            }
        }
        
        func calculateNextIndex(for usage: DerivationPath.Usage) -> UInt32 {
            UInt32(entriesByUsage[usage]?.count ?? 0)
        }
        
        func contains(address: Address) -> Bool {
            locateEntry(for: address) != nil
        }
        
        func findEntry(for address: Address) -> Entry? {
            guard let location = locateEntry(for: address),
                  let entries = entriesByUsage[location.usage] else {
                return nil
            }
            
            return entries[location.index]
        }
        
        mutating func append(_ entry: Entry, usage: DerivationPath.Usage) {
            var entries = entriesByUsage[usage, default: .init()]
            entries.append(entry)
            entriesByUsage[usage] = entries
        }
        
        mutating func updateEntry(at index: Int,
                                  usage: DerivationPath.Usage,
                                  _ update: (inout Entry) -> Void) {
            guard var entries = entriesByUsage[usage], entries.indices.contains(index) else { return }
            var entry = entries[index]
            update(&entry)
            entries[index] = entry
            entriesByUsage[usage] = entries
        }
        
        mutating func updateCacheValidityDuration(to newDuration: TimeInterval) {
            cacheValidityDurationValue = newDuration
            for (usage, storedEntries) in entriesByUsage {
                var updatedEntries = storedEntries
                for index in updatedEntries.indices {
                    updatedEntries[index].cache.validityDuration = newDuration
                }
                entriesByUsage[usage] = updatedEntries
            }
        }
        
        mutating func updateCache(for address: Address,
                                  balance: Satoshi,
                                  timestamp: Date) throws {
            let validityDuration = cacheValidityDurationValue
            _ = try updateEntry(for: address) { entry in
                entry.cache = Entry.Cache(balance: balance,
                                          lastUpdated: timestamp,
                                          validityDuration: validityDuration)
            }
        }
        
        mutating func mark(address: Address, isUsed: Bool) throws -> Entry {
            try updateEntry(for: address) { entry in
                entry.isUsed = isUsed
            }
        }
        
        private mutating func updateEntry(for address: Address,
                                          _ update: (inout Entry) -> Void) throws -> Entry {
            guard let location = locateEntry(for: address),
                  var entries = entriesByUsage[location.usage] else {
                throw Address.Book.Error.addressNotFound
            }
            
            var entry = entries[location.index]
            update(&entry)
            entries[location.index] = entry
            entriesByUsage[location.usage] = entries
            return entry
        }
        
        private func locateEntry(for address: Address) -> (usage: DerivationPath.Usage, index: Int)? {
            for usage in DerivationPath.Usage.allCases {
                guard let entries = entriesByUsage[usage],
                      let index = entries.firstIndex(where: { $0.address == address }) else {
                    continue
                }
                
                return (usage, index)
            }
            
            return nil
        }
    }
}

extension Address.Book.Inventory: Sendable {}
