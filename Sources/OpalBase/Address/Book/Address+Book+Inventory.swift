// Address+Book+Inventory.swift

import Foundation

extension Address.Book {
    public struct Inventory {
        private var entriesByUsage: [DerivationPath.Usage: [Entry]]
        private var addressToEntry: [Address: Entry]
        private var cacheValidityDurationValue: TimeInterval
        
        init(cacheValidityDuration: TimeInterval) {
            self.entriesByUsage = .init(uniqueKeysWithValues: DerivationPath.Usage.allCases.map { usage in (usage, .init()) } )
            self.addressToEntry = .init()
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
            UInt32(countEntries(for: usage))
        }
        
        func contains(address: Address) -> Bool {
            addressToEntry[address] != nil
        }
        
        func findEntry(for address: Address) -> Entry? {
            addressToEntry[address]
        }
        
        mutating func append(_ entry: Entry, usage: DerivationPath.Usage) {
            entriesByUsage[usage, default: .init()].append(entry)
            addressToEntry[entry.address] = entry
        }
        
        mutating func updateEntry(at index: Int,
                                  usage: DerivationPath.Usage,
                                  _ update: (inout Entry) -> Void) {
            guard var entries = entriesByUsage[usage], entries.indices.contains(index) else { return }
            var entry = entries[index]
            update(&entry)
            entries[index] = entry
            entriesByUsage[usage] = entries
            addressToEntry[entry.address] = entry
        }
        
        mutating func updateCacheValidityDuration(to newDuration: TimeInterval) {
            cacheValidityDurationValue = newDuration
            for usage in DerivationPath.Usage.allCases {
                guard let indices = entriesByUsage[usage]?.indices else { return }
                for index in indices {
                    updateEntry(at: index, usage: usage) { entry in
                        entry.cache.validityDuration = newDuration
                    }
                }
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
            guard let existingEntry = addressToEntry[address] else { throw Address.Book.Error.addressNotFound }
            
            let usage = existingEntry.derivationPath.usage
            guard var entries = entriesByUsage[usage],
                  let index = entries.firstIndex(where: { $0.address == address }) else {
                throw Address.Book.Error.addressNotFound
            }
            
            var entry = entries[index]
            update(&entry)
            entries[index] = entry
            entriesByUsage[usage] = entries
            addressToEntry[address] = entry
            return entry
        }
    }
}

extension Address.Book.Inventory: Sendable {}
