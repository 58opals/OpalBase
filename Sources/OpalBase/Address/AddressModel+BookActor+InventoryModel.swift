// AddressModel+BookActor+InventoryModel.swift

import Foundation

extension AddressModel.BookActor {
    struct InventoryModel {
        private var bucket: UsageBucketModel
        private var addressIndex: [AddressModel: (usage: DerivationPathModel.UsageModel, index: Int)]
        private var cacheValidityDurationValue: TimeInterval
        
        init(cacheValidityDuration: TimeInterval) {
            self.bucket = .init()
            self.addressIndex = .init()
            self.cacheValidityDurationValue = cacheValidityDuration
        }
        
        var allEntries: [EntryModel] {
            bucket.allEntries
        }
        
        var cacheValidityDuration: TimeInterval {
            cacheValidityDurationValue
        }
        
        func checkCacheValidity(_ cache: EntryModel.Cache, currentDate: Date) -> Bool {
            cache.checkValidity(currentDate: currentDate, validityDuration: cacheValidityDurationValue)
        }
        
        func listEntries(for usage: DerivationPathModel.UsageModel) -> [EntryModel] {
            bucket.fetchEntries(for: usage)
        }
        
        func countEntries(for usage: DerivationPathModel.UsageModel) -> Int {
            bucket.countEntries(for: usage)
        }
        
        func listUsedEntries(for usage: DerivationPathModel.UsageModel) -> Set<EntryModel> {
            Set(listEntries(for: usage).filter { $0.isUsed })
        }
        
        func countUnusedEntries(for usage: DerivationPathModel.UsageModel) -> Int {
            bucket.countUnusedEntries(for: usage)
        }
        
        func calculateNextIndex(for usage: DerivationPathModel.UsageModel) -> UInt32 {
            UInt32(bucket.countEntries(for: usage))
        }
        
        func contains(address: AddressModel) -> Bool {
            locateEntry(for: address) != nil
        }
        
        func findEntry(for address: AddressModel) -> EntryModel? {
            guard let location = locateEntry(for: address) else { return nil }
            return bucket.fetchEntry(at: location.index, usage: location.usage)
        }
        
        mutating func append(_ entry: EntryModel, usage: DerivationPathModel.UsageModel) {
            bucket.appendEntry(entry, usage: usage)
            let newIndex = bucket.countEntries(for: usage) - 1
            recordAddressIndex(for: entry, usage: usage, index: newIndex)
        }
        
        mutating func updateEntry(at index: Int,
                                  usage: DerivationPathModel.UsageModel,
                                  _ update: (inout EntryModel) -> Void) {
            _ = updateEntryAndIndex(at: index, usage: usage, update)
        }
        
        mutating func updateCacheValidityDuration(to newDuration: TimeInterval) {
            cacheValidityDurationValue = newDuration
        }
        
        mutating func updateCache(for address: AddressModel,
                                  balance: SatoshiModel,
                                  timestamp: Date) throws {
            _ = try updateEntry(for: address) { entry in
                entry.cache = EntryModel.Cache(balance: balance,
                                          lastUpdated: timestamp)
            }
        }
        
        mutating func mark(address: AddressModel, isUsed: Bool) throws -> EntryModel {
            try updateEntry(for: address) { entry in
                entry.isUsed = isUsed
                entry.isReserved = false
            }
        }
        
        mutating func reserve(address: AddressModel) throws -> EntryModel {
            guard let currentEntry = findEntry(for: address) else { throw AddressModel.BookActor.Error.addressNotFound }
            guard !currentEntry.isReserved else { throw AddressModel.BookActor.Error.entryAlreadyReserved(currentEntry) }
            
            return try updateEntry(for: address) { entry in
                entry.isUsed = true
                entry.isReserved = true
            }
        }
        
        mutating func releaseReservation(address: AddressModel, shouldKeepUsed: Bool) throws -> EntryModel {
            try updateEntry(for: address) { entry in
                entry.isUsed = shouldKeepUsed
                entry.isReserved = false
            }
        }
        
        private mutating func updateEntry(for address: AddressModel,
                                          _ update: (inout EntryModel) -> Void) throws -> EntryModel {
            guard let location = locateEntry(for: address),
                  let updatedEntry = updateEntryAndIndex(at: location.index,
                                                         usage: location.usage,
                                                         update) else {
                throw AddressModel.BookActor.Error.addressNotFound
            }
            
            return updatedEntry
        }
        
        private func locateEntry(for address: AddressModel) -> (usage: DerivationPathModel.UsageModel, index: Int)? {
            addressIndex[address]
        }
        
        private mutating func updateEntryAndIndex(at index: Int,
                                                  usage: DerivationPathModel.UsageModel,
                                                  _ update: (inout EntryModel) -> Void) -> EntryModel? {
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
        
        private mutating func recordAddressIndex(for entry: EntryModel,
                                                 usage: DerivationPathModel.UsageModel,
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
        
        private mutating func refreshAddressIndex(oldEntry: EntryModel,
                                                  updatedEntry: EntryModel,
                                                  usage: DerivationPathModel.UsageModel,
                                                  index: Int) {
            if oldEntry.address == updatedEntry.address {
                recordAddressIndex(for: updatedEntry, usage: usage, index: index)
                return
            }
            
            removeAddressIndex(for: oldEntry, usage: usage, index: index)
            recordAddressIndex(for: updatedEntry, usage: usage, index: index)
        }
        
        private mutating func removeAddressIndex(for entry: EntryModel,
                                                 usage: DerivationPathModel.UsageModel,
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

extension AddressModel.BookActor.InventoryModel: Sendable {}
