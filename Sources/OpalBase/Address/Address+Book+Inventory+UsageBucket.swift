// Address+Book+Inventory+UsageBucket.swift

import Foundation

extension Address.Book.Inventory {
    struct UsageBucket {
        var receivingEntries: [Address.Book.Entry]
        var changeEntries: [Address.Book.Entry]
        
        init() {
            self.receivingEntries = .init()
            self.changeEntries = .init()
        }
        
        var allEntries: [Address.Book.Entry] {
            receivingEntries + changeEntries
        }
        
        func fetchEntries(for usage: DerivationPath.Usage) -> [Address.Book.Entry] {
            switch usage {
            case .receiving:
                return receivingEntries
            case .change:
                return changeEntries
            }
        }
        
        func countEntries(for usage: DerivationPath.Usage) -> Int {
            fetchEntries(for: usage).count
        }
        
        func countUnusedEntries(for usage: DerivationPath.Usage) -> Int {
            calculateUnusedEntryCount(in: fetchEntries(for: usage))
        }
        
        func fetchEntry(at index: Int, usage: DerivationPath.Usage) -> Address.Book.Entry? {
            let entries = fetchEntries(for: usage)
            return entries.indices.contains(index) ? entries[index] : nil
        }
        
        func locateEntry(for address: Address) -> (usage: DerivationPath.Usage, index: Int)? {
            if let index = receivingEntries.firstIndex(where: { $0.address == address }) {
                return (.receiving, index)
            }
            
            if let index = changeEntries.firstIndex(where: { $0.address == address }) {
                return (.change, index)
            }
            
            return nil
        }
        
        mutating func appendEntry(_ entry: Address.Book.Entry, usage: DerivationPath.Usage) {
            updateEntries(for: usage) { $0.append(entry) }
        }
        
        mutating func updateEntry(at index: Int,
                                  usage: DerivationPath.Usage,
                                  _ update: (inout Address.Book.Entry) -> Void) -> Address.Book.Entry? {
            var updatedEntry: Address.Book.Entry?
            updateEntries(for: usage) { entries in
                guard entries.indices.contains(index) else { return }
                update(&entries[index])
                updatedEntry = entries[index]
            }
            return updatedEntry
        }
        
        mutating func updateAllEntries(_ update: (inout Address.Book.Entry) -> Void) {
            for index in receivingEntries.indices {
                update(&receivingEntries[index])
            }
            
            for index in changeEntries.indices {
                update(&changeEntries[index])
            }
        }
        
        private mutating func updateEntries(for usage: DerivationPath.Usage,
                                            _ mutate: (inout [Address.Book.Entry]) -> Void) {
            switch usage {
            case .receiving:
                mutate(&receivingEntries)
            case .change:
                mutate(&changeEntries)
            }
        }
        
        private func calculateUnusedEntryCount(in entries: [Address.Book.Entry]) -> Int {
            entries.reduce(into: 0) { result, entry in
                if !entry.isUsed {
                    result += 1
                }
            }
        }
    }
}

extension Address.Book.Inventory.UsageBucket: Sendable {}
