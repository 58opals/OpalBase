// Address+Book+Entry.swift

import Foundation

extension Address.Book {
    public struct Entry {
        public let address: Address
        public let derivationPath: DerivationPath
        public let createdAt: Date
        var isUsed: Bool
        var cache: Cache
        
        init(address: Address, derivationPath: DerivationPath, createdAt: Date = .init(), isUsed: Bool, cache: Cache = .init()) {
            self.address = address
            self.derivationPath = derivationPath
            self.createdAt = createdAt
            self.isUsed = isUsed
            self.cache = cache
        }
    }
}

// MARK: - Initialize
extension Address.Book {
    func initializeEntries() async throws {
        try await generateEntries(for: .receiving,
                                  numberOfNewEntries: gapLimit,
                                  isUsed: false)
        try await generateEntries(for: .change,
                                  numberOfNewEntries: gapLimit,
                                  isUsed: false)
    }
}

// MARK: - Generate
extension Address.Book {
    func generateEntriesIfNeeded(for usage: DerivationPath.Usage) async throws {
        let numberOfRemainingUnusedEntries = inventory.countUnusedEntries(for: usage)
        if numberOfRemainingUnusedEntries < gapLimit {
            try await generateEntries(for: usage,
                                      numberOfNewEntries: gapLimit,
                                      isUsed: false)
        }
    }
    
    func generateEntries(for usage: DerivationPath.Usage,
                         numberOfNewEntries: Int,
                         isUsed: Bool) async throws {
        guard numberOfNewEntries > 0 else { return }
        
        let currentCount = inventory.countEntries(for: usage)
        let cacheValidityDuration = inventory.cacheValidityDuration
        let desiredCount = currentCount + numberOfNewEntries
        
        for nextIndexValue in currentCount ..< desiredCount {
            guard let nextIndex = UInt32(exactly: nextIndexValue) else { throw Error.indexOutOfBounds }
            
            let newEntry = try makeEntry(for: usage,
                                         index: nextIndex,
                                         isUsed: isUsed,
                                         cacheValidityDuration: cacheValidityDuration)
            inventory.append(newEntry, usage: usage)
            await notifyNewEntry(newEntry)
        }
    }
    
    private func makeEntry(for usage: DerivationPath.Usage,
                           index: UInt32,
                           isUsed: Bool,
                           cacheValidityDuration: TimeInterval) throws -> Entry {
        let address = try generateAddress(at: index, for: usage)
        let derivationPath = try createDerivationPath(usage: usage, index: index)
        
        if let existingEntry = inventory.findEntry(for: address) { throw Error.entryDuplicated(existingEntry) }
        
        return Entry(address: address,
                     derivationPath: derivationPath,
                     isUsed: isUsed,
                     cache: .init(validityDuration: cacheValidityDuration))
    }
}

// MARK: - Get
extension Address.Book {
    public func selectNextEntry(for usage: DerivationPath.Usage) async throws -> Entry {
        try await generateEntriesIfNeeded(for: usage)
        
        let entries = inventory.listEntries(for: usage)
        guard let nextEntry = entries.first(where: { !$0.isUsed }) else { throw Error.entryNotFound }
        
        return nextEntry
    }
}

// MARK: - Mark
extension Address.Book {
    func checkUsageStatus(of address: Address) throws -> Bool {
        guard let entry = inventory.findEntry(for: address) else { throw Error.addressNotFound }
        return entry.isUsed
    }
    
    func mark(address: Address, isUsed: Bool) async throws {
        let entry = try inventory.mark(address: address, isUsed: isUsed)
        try await generateEntriesIfNeeded(for: entry.derivationPath.usage)
    }
}

extension Address.Book.Entry: Hashable {}
extension Address.Book.Entry: Sendable {}
