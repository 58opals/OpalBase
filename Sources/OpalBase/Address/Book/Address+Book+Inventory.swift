// Address+Book+Inventory.swift

import Foundation

extension Address.Book {
    struct Inventory {
        private struct Position {
            let usage: DerivationPath.Usage
            let index: Int
        }
        
        private var receivingEntries: [Entry]
        private var changeEntries: [Entry]
        private var addressToEntry: [Address: Entry]
        private var addressToPosition: [Address: Position]
        
        init() {
            self.receivingEntries = .init()
            self.changeEntries = .init()
            self.addressToEntry = .init()
            self.addressToPosition = .init()
        }
        
        var allEntries: [Entry] {
            receivingEntries + changeEntries
        }
        
        func entries(for usage: DerivationPath.Usage) -> [Entry] {
            switch usage {
            case .receiving: return receivingEntries
            case .change: return changeEntries
            }
        }
        
        func count(for usage: DerivationPath.Usage) -> Int {
            entries(for: usage).count
        }
        
        func usedEntries(for usage: DerivationPath.Usage) -> Set<Entry> {
            Set(entries(for: usage).filter { $0.isUsed })
        }
        
        func contains(address: Address) -> Bool {
            addressToEntry[address] != nil
        }
        
        func entry(for address: Address) -> Entry? {
            addressToEntry[address]
        }
        
        mutating func append(_ entry: Entry, usage: DerivationPath.Usage) {
            let index: Int
            switch usage {
            case .receiving:
                index = receivingEntries.count
                receivingEntries.append(entry)
            case .change:
                index = changeEntries.count
                changeEntries.append(entry)
            }
            
            let position = Position(usage: usage, index: index)
            addressToEntry[entry.address] = entry
            addressToPosition[entry.address] = position
        }
        
        mutating func updateEntry(at index: Int,
                                  usage: DerivationPath.Usage,
                                  _ update: (inout Entry) -> Void) {
            let position = Position(usage: usage, index: index)
            var entry = readEntry(at: position)
            update(&entry)
            setEntry(entry, at: position)
        }
        
        mutating func updateCacheValidityDuration(to newDuration: TimeInterval) {
            for index in receivingEntries.indices {
                updateEntry(at: index, usage: .receiving) { entry in
                    entry.cache.validityDuration = newDuration
                }
            }
            
            for index in changeEntries.indices {
                updateEntry(at: index, usage: .change) { entry in
                    entry.cache.validityDuration = newDuration
                }
            }
        }
        
        mutating func updateCache(for address: Address,
                                  balance: Satoshi,
                                  validityDuration: TimeInterval,
                                  timestamp: Date) throws {
            let position = try position(for: address)
            var entry = readEntry(at: position)
            entry.cache = Entry.Cache(balance: balance,
                                      lastUpdated: timestamp,
                                      validityDuration: validityDuration)
            setEntry(entry, at: position)
        }
        
        mutating func mark(address: Address, isUsed: Bool) throws -> Entry {
            let position = try position(for: address)
            var entry = readEntry(at: position)
            entry.isUsed = isUsed
            setEntry(entry, at: position)
            return entry
        }
        
        private func readEntry(at position: Position) -> Entry {
            switch position.usage {
            case .receiving: return receivingEntries[position.index]
            case .change: return changeEntries[position.index]
            }
        }
        
        private mutating func setEntry(_ entry: Entry, at position: Position) {
            switch position.usage {
            case .receiving: receivingEntries[position.index] = entry
            case .change: changeEntries[position.index] = entry
            }
            addressToEntry[entry.address] = entry
            addressToPosition[entry.address] = position
        }
        
        private func position(for address: Address) throws -> Position {
            guard let position = addressToPosition[address] else { throw Address.Book.Error.addressNotFound }
            return position
        }
    }
}

extension Address.Book.Inventory: Sendable {}
