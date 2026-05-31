// OpalBase+Address+Book+Entry.swift

import Foundation

extension _OpalBase.Address.Book {
    struct Entry {
        let address: OpalBase.Address
        let derivationPath: OpalBase.Key.DerivationPath
        let createdAt: Date
        var isUsed: Bool
        var isReserved: Bool
        var cache: Cache
        
        init(address: OpalBase.Address,
             derivationPath: OpalBase.Key.DerivationPath,
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
extension _OpalBase.Address.Book {
    func initializeEntries() async throws {
        for usage in OpalBase.Key.DerivationPath.Usage.allCases {
            try await generateEntries(for: usage,
                                      entryCount: gapLimit,
                                      isUsed: false)
        }
    }
}

// MARK: - Generate
extension _OpalBase.Address.Book {
    func generateEntriesIfNeeded(for usage: OpalBase.Key.DerivationPath.Usage) async throws {
        let numberOfRemainingUnusedEntries = inventory.countUnusedEntries(for: usage)
        guard numberOfRemainingUnusedEntries < gapLimit else { return }
        
        let numberOfMissingEntries = gapLimit - numberOfRemainingUnusedEntries
        guard numberOfMissingEntries > 0 else { return }
        
        try await generateEntries(for: usage,
                                  entryCount: numberOfMissingEntries,
                                  isUsed: false)
    }
    
    func generateEntries(for usage: OpalBase.Key.DerivationPath.Usage,
                         entryCount: Int,
                         isUsed: Bool,
                         shouldNotifyNewEntries: Bool = true) async throws {
        guard entryCount > 0 else { return }
        
        let currentCount = inventory.countEntries(for: usage)
        let desiredCount = currentCount + entryCount
        
        var indices: [UInt32] = .init()
        indices.reserveCapacity(entryCount)
        for indexValue in currentCount ..< desiredCount {
            guard let index = UInt32(exactly: indexValue) else { throw Error.indexOutOfBounds }
            indices.append(index)
        }
        
        let newEntries: [Entry]
        if let cachedUsageDerivation = usageDerivationCache[usage] {
            newEntries = try await makeEntriesUsingUsageDerivationCache(usage: usage,
                                                                        indices: indices,
                                                                        cachedUsageDerivation: cachedUsageDerivation,
                                                                        isUsed: isUsed)
        } else {
            newEntries = try indices.map { index in
                try makeEntry(for: usage,
                              index: index,
                              isUsed: isUsed)
            }
        }
        
        for newEntry in newEntries {
            inventory.append(newEntry, usage: usage)
            if shouldNotifyNewEntries {
                await notifyNewEntry(newEntry)
            }
        }
    }
    
    private func makeEntry(for usage: OpalBase.Key.DerivationPath.Usage,
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
    
    private func makeEntriesUsingUsageDerivationCache(
        usage: OpalBase.Key.DerivationPath.Usage,
        indices: [UInt32],
        cachedUsageDerivation: UsageDerivationCache,
        isUsed: Bool
    ) async throws -> [Entry] {
        var childPrivateKeys: [Data] = .init()
        childPrivateKeys.reserveCapacity(indices.count)
        var derivationPaths: [OpalBase.Key.DerivationPath] = .init()
        derivationPaths.reserveCapacity(indices.count)
        
        for index in indices {
            let derivationPath = try createDerivationPath(usage: usage, index: index)
            let childExtendedPrivateKey = try cachedUsageDerivation.baseExtendedPrivateKey.derived(indices: [index])
            childPrivateKeys.append(childExtendedPrivateKey.privateKey.rawRepresentation)
            derivationPaths.append(derivationPath)
        }
        
        let compressedPublicKeys = try await OpalCryptoAdapter.deriveCompressedPublicKeys(
            from: childPrivateKeys
        )
        var entries: [Entry] = .init()
        entries.reserveCapacity(indices.count)
        
        for (position, compressedPublicKey) in compressedPublicKeys.enumerated() {
            let address = try makeAddress(fromCompressedPublicKey: compressedPublicKey)
            if let existingEntry = inventory.findEntry(for: address) { throw Error.entryDuplicated(existingEntry) }
            
            entries.append(Entry(address: address,
                                 derivationPath: derivationPaths[position],
                                 isUsed: isUsed,
                                 isReserved: false))
        }
        
        return entries
    }
}

// MARK: - Get
extension _OpalBase.Address.Book {
    func selectNextEntry(for usage: OpalBase.Key.DerivationPath.Usage) async throws -> Entry {
        try await generateEntriesIfNeeded(for: usage)
        
        let entries = inventory.listEntries(for: usage)
        guard let nextEntry = entries.first(where: { !$0.isUsed && !$0.isReserved }) else { throw Error.entryNotFound }
        
        return nextEntry
    }
    
    func reserveNextEntry(for usage: OpalBase.Key.DerivationPath.Usage) async throws -> Entry {
        let nextEntry = try await selectNextEntry(for: usage)
        return try await reserveEntryMaintainingGap(nextEntry)
    }

    func reserveEntryMaintainingGap(_ candidateEntry: Entry) async throws -> Entry {
        let reservedEntry = try reserveEntry(address: candidateEntry.address)
        do {
            try await generateEntriesIfNeeded(for: reservedEntry.derivationPath.usage)
            return reservedEntry
        } catch {
            _ = try? releaseReservation(address: reservedEntry.address,
                                        shouldKeepUsed: candidateEntry.isUsed)
            throw error
        }
    }
}

// MARK: - Mark
extension _OpalBase.Address.Book {
    func isAddressUsed(_ address: OpalBase.Address) throws -> Bool {
        guard let entry = inventory.findEntry(for: address) else { throw Error.addressNotFound }
        return entry.isUsed
    }
    
    func mark(address: OpalBase.Address, isUsed: Bool) async throws {
        let entry = try inventory.mark(address: address, isUsed: isUsed)
        try await generateEntriesIfNeeded(for: entry.derivationPath.usage)
    }
}

extension _OpalBase.Address.Book.Entry: Sendable {}
extension _OpalBase.Address.Book.Entry: Hashable {}
extension _OpalBase.Address.Book.Entry: Equatable {}
