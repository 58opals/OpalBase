// Address+Book+Entry.swift

import Foundation

extension Address.Book {
    public struct Entry {
        public let address: Address
        public let derivationPath: DerivationPath
        public let createdAt: Date
        var isUsed: Bool
        var isReserved: Bool
        var cache: Cache
        
        init(address: Address,
             derivationPath: DerivationPath,
             createdAt: Date = .init(),
             isUsed: Bool,
             isReserved: Bool,
             cache: Cache = .init()) {
            self.address = address
            self.derivationPath = derivationPath
            self.createdAt = createdAt
            self.isUsed = isUsed
            self.isReserved = isReserved
            self.cache = cache
        }
    }
}

// MARK: - Initialize
extension Address.Book {
    func initializeEntries() async throws {
        for usage in DerivationPath.Usage.allCases {
            try await generateEntries(for: usage,
                                      numberOfNewEntries: gapLimit,
                                      isUsed: false)
        }
    }
}

// MARK: - Generate
extension Address.Book {
    func generateEntriesIfNeeded(for usage: DerivationPath.Usage) async throws {
        let numberOfRemainingUnusedEntries = inventory.countUnusedEntries(for: usage)
        guard numberOfRemainingUnusedEntries < gapLimit else { return }
        
        let numberOfMissingEntries = gapLimit - numberOfRemainingUnusedEntries
        guard numberOfMissingEntries > 0 else { return }
        
        try await generateEntries(for: usage,
                                  numberOfNewEntries: numberOfMissingEntries,
                                  isUsed: false)
    }
    
    func generateEntries(for usage: DerivationPath.Usage,
                         numberOfNewEntries: Int,
                         isUsed: Bool) async throws {
        guard numberOfNewEntries > 0 else { return }
        
        let currentCount = inventory.countEntries(for: usage)
        let desiredCount = currentCount + numberOfNewEntries
        
        for nextIndexValue in currentCount ..< desiredCount {
            guard let nextIndex = UInt32(exactly: nextIndexValue) else { throw Error.indexOutOfBounds }
            
            let newEntry = try makeEntry(for: usage,
                                         index: nextIndex,
                                         isUsed: isUsed)
            inventory.append(newEntry, usage: usage)
            await notifyNewEntry(newEntry)
        }
    }
    
    private func makeEntry(for usage: DerivationPath.Usage,
                           index: UInt32,
                           isUsed: Bool) throws -> Entry {
        let address = try generateAddress(at: index, for: usage)
        let derivationPath = try createDerivationPath(usage: usage, index: index)
        
        if let existingEntry = inventory.findEntry(for: address) { throw Error.entryDuplicated(existingEntry) }
        
        return Entry(address: address,
                     derivationPath: derivationPath,
                     isUsed: isUsed,
                     isReserved: false)
    }
}

// MARK: - Get
extension Address.Book {
    public func selectNextEntry(for usage: DerivationPath.Usage) async throws -> Entry {
        try await generateEntriesIfNeeded(for: usage)
        
        let entries = inventory.listEntries(for: usage)
        guard let nextEntry = entries.first(where: { !$0.isUsed && !$0.isReserved }) else { throw Error.entryNotFound }
        
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
extension Address.Book.Entry: Equatable {}
