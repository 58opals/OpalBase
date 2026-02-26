// AddressModel+BookActor+InventoryModel+UsageBucketModel.swift

import Foundation

extension AddressModel.BookActor.InventoryModel {
    struct UsageBucketModel {
        var receivingEntries: [AddressModel.BookActor.EntryModel]
        var changeEntries: [AddressModel.BookActor.EntryModel]
        
        init() {
            self.receivingEntries = .init()
            self.changeEntries = .init()
        }
        
        var allEntries: [AddressModel.BookActor.EntryModel] {
            receivingEntries + changeEntries
        }
        
        func fetchEntries(for usage: DerivationPathModel.UsageModel) -> [AddressModel.BookActor.EntryModel] {
            switch usage {
            case .receiving:
                return receivingEntries
            case .change:
                return changeEntries
            }
        }
        
        func countEntries(for usage: DerivationPathModel.UsageModel) -> Int {
            fetchEntries(for: usage).count
        }
        
        func countUnusedEntries(for usage: DerivationPathModel.UsageModel) -> Int {
            calculateUnusedEntryCount(in: fetchEntries(for: usage))
        }
        
        func fetchEntry(at index: Int, usage: DerivationPathModel.UsageModel) -> AddressModel.BookActor.EntryModel? {
            let entries = fetchEntries(for: usage)
            return entries.indices.contains(index) ? entries[index] : nil
        }
        
        mutating func appendEntry(_ entry: AddressModel.BookActor.EntryModel, usage: DerivationPathModel.UsageModel) {
            updateEntries(for: usage) { $0.append(entry) }
        }
        
        mutating func updateEntry(at index: Int,
                                  usage: DerivationPathModel.UsageModel,
                                  _ update: (inout AddressModel.BookActor.EntryModel) -> Void) -> AddressModel.BookActor.EntryModel? {
            var updatedEntry: AddressModel.BookActor.EntryModel?
            updateEntries(for: usage) { entries in
                guard entries.indices.contains(index) else { return }
                update(&entries[index])
                updatedEntry = entries[index]
            }
            return updatedEntry
        }
        
        mutating func updateAllEntries(_ update: (inout AddressModel.BookActor.EntryModel) -> Void) {
            for index in receivingEntries.indices {
                update(&receivingEntries[index])
            }
            
            for index in changeEntries.indices {
                update(&changeEntries[index])
            }
        }
        
        private mutating func updateEntries(for usage: DerivationPathModel.UsageModel,
                                            _ mutate: (inout [AddressModel.BookActor.EntryModel]) -> Void) {
            switch usage {
            case .receiving:
                mutate(&receivingEntries)
            case .change:
                mutate(&changeEntries)
            }
        }
        
        private func calculateUnusedEntryCount(in entries: [AddressModel.BookActor.EntryModel]) -> Int {
            entries.reduce(into: 0) { result, entry in
                if !entry.isUsed {
                    result += 1
                }
            }
        }
    }
}

extension AddressModel.BookActor.InventoryModel.UsageBucketModel: Sendable {}
