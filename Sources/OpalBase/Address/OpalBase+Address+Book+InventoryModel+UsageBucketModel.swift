// OpalBase+Address+Book+InventoryModel+UsageBucketModel.swift

import Foundation

extension _OpalBase.Address.Book.InventoryModel {
    struct UsageBucketModel {
        var receivingEntries: [OpalBase.Address.Book.EntryModel]
        var changeEntries: [OpalBase.Address.Book.EntryModel]
        
        init() {
            self.receivingEntries = .init()
            self.changeEntries = .init()
        }
        
        var allEntries: [OpalBase.Address.Book.EntryModel] {
            receivingEntries + changeEntries
        }
        
        func fetchEntries(for usage: OpalBase.DerivationPath.UsageModel) -> [OpalBase.Address.Book.EntryModel] {
            switch usage {
            case .receiving:
                return receivingEntries
            case .change:
                return changeEntries
            }
        }
        
        func countEntries(for usage: OpalBase.DerivationPath.UsageModel) -> Int {
            fetchEntries(for: usage).count
        }
        
        func countUnusedEntries(for usage: OpalBase.DerivationPath.UsageModel) -> Int {
            calculateUnusedEntryCount(in: fetchEntries(for: usage))
        }
        
        func fetchEntry(at index: Int, usage: OpalBase.DerivationPath.UsageModel) -> OpalBase.Address.Book.EntryModel? {
            let entries = fetchEntries(for: usage)
            return entries.indices.contains(index) ? entries[index] : nil
        }
        
        mutating func appendEntry(_ entry: OpalBase.Address.Book.EntryModel, usage: OpalBase.DerivationPath.UsageModel) {
            updateEntries(for: usage) { $0.append(entry) }
        }
        
        mutating func updateEntry(at index: Int,
                                  usage: OpalBase.DerivationPath.UsageModel,
                                  _ update: (inout OpalBase.Address.Book.EntryModel) -> Void) -> OpalBase.Address.Book.EntryModel? {
            var updatedEntry: OpalBase.Address.Book.EntryModel?
            updateEntries(for: usage) { entries in
                guard entries.indices.contains(index) else { return }
                update(&entries[index])
                updatedEntry = entries[index]
            }
            return updatedEntry
        }
        
        mutating func updateAllEntries(_ update: (inout OpalBase.Address.Book.EntryModel) -> Void) {
            for index in receivingEntries.indices {
                update(&receivingEntries[index])
            }
            
            for index in changeEntries.indices {
                update(&changeEntries[index])
            }
        }
        
        private mutating func updateEntries(for usage: OpalBase.DerivationPath.UsageModel,
                                            _ mutate: (inout [OpalBase.Address.Book.EntryModel]) -> Void) {
            switch usage {
            case .receiving:
                mutate(&receivingEntries)
            case .change:
                mutate(&changeEntries)
            }
        }
        
        private func calculateUnusedEntryCount(in entries: [OpalBase.Address.Book.EntryModel]) -> Int {
            entries.reduce(into: 0) { result, entry in
                if !entry.isUsed {
                    result += 1
                }
            }
        }
    }
}

extension _OpalBase.Address.Book.InventoryModel.UsageBucketModel: Sendable {}
