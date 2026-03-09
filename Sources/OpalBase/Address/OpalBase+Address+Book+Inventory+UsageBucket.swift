// OpalBase+Address+Book+Inventory+UsageBucket.swift

import Foundation

extension _OpalBase.Address.Book.Inventory {
    struct UsageBucket {
        var receivingEntries: [OpalBase.Address.Book.Entry]
        var changeEntries: [OpalBase.Address.Book.Entry]
        
        init() {
            self.receivingEntries = .init()
            self.changeEntries = .init()
        }
        
        var allEntries: [OpalBase.Address.Book.Entry] {
            receivingEntries + changeEntries
        }
        
        func fetchEntries(for usage: OpalBase.DerivationPath.Usage) -> [OpalBase.Address.Book.Entry] {
            switch usage {
            case .receiving:
                return receivingEntries
            case .change:
                return changeEntries
            }
        }
        
        func countEntries(for usage: OpalBase.DerivationPath.Usage) -> Int {
            fetchEntries(for: usage).count
        }
        
        func countUnusedEntries(for usage: OpalBase.DerivationPath.Usage) -> Int {
            calculateUnusedEntryCount(in: fetchEntries(for: usage))
        }
        
        func fetchEntry(at index: Int, usage: OpalBase.DerivationPath.Usage) -> OpalBase.Address.Book.Entry? {
            let entries = fetchEntries(for: usage)
            return entries.indices.contains(index) ? entries[index] : nil
        }
        
        mutating func appendEntry(_ entry: OpalBase.Address.Book.Entry, usage: OpalBase.DerivationPath.Usage) {
            updateEntries(for: usage) { $0.append(entry) }
        }
        
        mutating func updateEntry(at index: Int,
                                  usage: OpalBase.DerivationPath.Usage,
                                  _ update: (inout OpalBase.Address.Book.Entry) -> Void) -> OpalBase.Address.Book.Entry? {
            var updatedEntry: OpalBase.Address.Book.Entry?
            updateEntries(for: usage) { entries in
                guard entries.indices.contains(index) else { return }
                update(&entries[index])
                updatedEntry = entries[index]
            }
            return updatedEntry
        }
        
        mutating func updateAllEntries(_ update: (inout OpalBase.Address.Book.Entry) -> Void) {
            for index in receivingEntries.indices {
                update(&receivingEntries[index])
            }
            
            for index in changeEntries.indices {
                update(&changeEntries[index])
            }
        }
        
        private mutating func updateEntries(for usage: OpalBase.DerivationPath.Usage,
                                            _ mutate: (inout [OpalBase.Address.Book.Entry]) -> Void) {
            switch usage {
            case .receiving:
                mutate(&receivingEntries)
            case .change:
                mutate(&changeEntries)
            }
        }
        
        private func calculateUnusedEntryCount(in entries: [OpalBase.Address.Book.Entry]) -> Int {
            entries.reduce(into: 0) { result, entry in
                if !entry.isUsed {
                    result += 1
                }
            }
        }
    }
}

extension _OpalBase.Address.Book.Inventory.UsageBucket: Sendable {}
