// OpalBase+Address+Book+Entry.swift

import Foundation

extension _OpalBase.Address.Book {
    public struct Entry {
        public let address: OpalBase.Address
        public let derivationPath: OpalBase.Key.DerivationPath
        public let createdAt: Date
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
                                      numberOfNewEntries: gapLimit,
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
                                  numberOfNewEntries: numberOfMissingEntries,
                                  isUsed: false)
    }
    
    func generateEntries(for usage: OpalBase.Key.DerivationPath.Usage,
                         numberOfNewEntries: Int,
                         isUsed: Bool,
                         shouldNotifyNewEntries: Bool = true) async throws {
        guard numberOfNewEntries > 0 else { return }
        
        let currentCount = inventory.countEntries(for: usage)
        let desiredCount = currentCount + numberOfNewEntries
        
        var indices: [UInt32] = .init()
        indices.reserveCapacity(numberOfNewEntries)
        for indexValue in currentCount ..< desiredCount {
            guard let index = UInt32(exactly: indexValue) else { throw Error.indexOutOfBounds }
            indices.append(index)
        }
        
        let newEntries: [Entry]
        if let usageCache = usageDerivationCache[usage] {
            newEntries = try await makeEntriesUsingUsageDerivationCache(usage: usage,
                                                                        indices: indices,
                                                                        usageCache: usageCache,
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
        usageCache: UsageDerivationCache,
        isUsed: Bool
    ) async throws -> [Entry] {
        var childPrivateKeys: [Data] = .init()
        childPrivateKeys.reserveCapacity(indices.count)
        var derivationPaths: [OpalBase.Key.DerivationPath] = .init()
        derivationPaths.reserveCapacity(indices.count)
        
        for index in indices {
            let childExtendedPrivateKey = try usageCache.baseExtendedPrivateKey.derived(indices: [index])
            childPrivateKeys.append(childExtendedPrivateKey.privateKey)
            derivationPaths.append(try createDerivationPath(usage: usage, index: index))
        }
        
        let compressedPublicKeys = try await OpalCryptoAdapter.deriveCompressedPublicKeys(
            from: childPrivateKeys
        )
        var entries: [Entry] = .init()
        entries.reserveCapacity(indices.count)
        
        for (position, compressedPublicKey) in compressedPublicKeys.enumerated() {
            let publicKey = try OpalBase.Key.PublicKey(compressedData: compressedPublicKey)
            let address = try OpalBase.Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
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
    public func selectNextEntry(for usage: OpalBase.Key.DerivationPath.Usage) async throws -> Entry {
        try await generateEntriesIfNeeded(for: usage)
        
        let entries = inventory.listEntries(for: usage)
        guard let nextEntry = entries.first(where: { !$0.isUsed && !$0.isReserved }) else { throw Error.entryNotFound }
        
        return nextEntry
    }
    
    public func reserveNextEntry(for usage: OpalBase.Key.DerivationPath.Usage) async throws -> Entry {
        let nextEntry = try await selectNextEntry(for: usage)
        let reservedEntry = try reserveEntry(address: nextEntry.address)
        try await generateEntriesIfNeeded(for: reservedEntry.derivationPath.usage)
        
        return reservedEntry
    }
}

// MARK: - Mark
extension _OpalBase.Address.Book {
    func checkUsageStatus(of address: OpalBase.Address) throws -> Bool {
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
