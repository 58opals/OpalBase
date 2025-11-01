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
        let entries = listEntries(for: usage)
        let usedEntries = listUsedEntries(for: usage)
        
        let numberOfRemainingUnusedEntries = entries.count - usedEntries.count
        if numberOfRemainingUnusedEntries < gapLimit {
            try await generateEntries(for: usage,
                                      numberOfNewEntries: gapLimit,
                                      isUsed: false)
        }
    }
    
    func generateEntries(for usage: DerivationPath.Usage,
                         numberOfNewEntries: Int,
                         isUsed: Bool) async throws {
        let numberOfExistingEntries = inventory.countEntries(for: usage)
        
        for _ in numberOfExistingEntries ..< numberOfExistingEntries + numberOfNewEntries {
            try await generateEntry(for: usage,
                                    isUsed: isUsed)
        }
    }
    
    /// Generates a new entry for the specified usage.
    /// - Parameters:
    ///   - usage: The usage type (`.receiving` or `.change`).
    ///   - isUsed: Indicates whether the address is already used.
    /// - Throws: An error if entry generation fails.
    func generateEntry(for usage: DerivationPath.Usage,
                       isUsed: Bool) async throws {
        let nextIndex = UInt32(inventory.countEntries(for: usage))
        
        let address = try generateAddress(at: nextIndex, for: usage)
        let derivationPath = try createDerivationPath(usage: usage,
                                                      index: nextIndex)
        
        if let existingEntry = findEntry(for: address) { throw Error.entryDuplicated(existingEntry) }
        
        let newEntry = Entry(address: address,
                             derivationPath: derivationPath,
                             isUsed: isUsed,
                             cache: .init(validityDuration: cacheValidityDuration))
        
        inventory.append(newEntry, usage: usage)
        await notifyNewEntry(newEntry)
    }
}

// MARK: - Find
extension Address.Book {
    func findEntry(for address: Address) -> Entry? {
        return inventory.findEntry(for: address)
    }
}

// MARK: - Get
extension Address.Book {
    public func selectNextEntry(for usage: DerivationPath.Usage, shouldFetchBalance: Bool = true) async throws -> Entry {
        try await generateEntriesIfNeeded(for: usage)
        
        let entries = listEntries(for: usage)
        guard let nextEntry = entries.first(where: { !$0.isUsed }) else { throw Error.entryNotFound }
        
        return nextEntry
    }
    
    public func listEntries(for usage: DerivationPath.Usage) -> [Entry] {
        inventory.listEntries(for: usage)
    }
    
    public func listUsedEntries(for usage: DerivationPath.Usage) -> Set<Entry> {
        inventory.listUsedEntries(for: usage)
    }
}

// MARK: - Mark
extension Address.Book {
    func checkUsageStatus(of address: Address) throws -> Bool {
        guard let entry = findEntry(for: address) else { throw Error.addressNotFound }
        return entry.isUsed
    }
    
    func mark(address: Address, isUsed: Bool) async throws {
        let entry = try inventory.mark(address: address, isUsed: isUsed)
        try await generateEntriesIfNeeded(for: entry.derivationPath.usage)
    }
}

extension Address.Book.Entry: Hashable {}
extension Address.Book.Entry: Sendable {}
