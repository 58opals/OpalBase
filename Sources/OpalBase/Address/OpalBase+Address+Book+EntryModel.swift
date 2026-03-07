// OpalBase.Address+BookActor+EntryModel.swift

import Foundation

extension _OpalBase.Address.Book {
    public struct EntryModel {
        public let address: OpalBase.Address
        public let derivationPath: OpalBase.DerivationPath
        public let createdAt: Date
        var isUsed: Bool
        var isReserved: Bool
        var cache: Cache
        
        init(address: OpalBase.Address,
             derivationPath: OpalBase.DerivationPath,
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
        for usage in OpalBase.DerivationPath.UsageModel.allCases {
            try await generateEntries(for: usage,
                                      numberOfNewEntries: gapLimit,
                                      isUsed: false)
        }
    }
}

// MARK: - Generate
extension _OpalBase.Address.Book {
    func generateEntriesIfNeeded(for usage: OpalBase.DerivationPath.UsageModel) async throws {
        let numberOfRemainingUnusedEntries = inventory.countUnusedEntries(for: usage)
        guard numberOfRemainingUnusedEntries < gapLimit else { return }
        
        let numberOfMissingEntries = gapLimit - numberOfRemainingUnusedEntries
        guard numberOfMissingEntries > 0 else { return }
        
        try await generateEntries(for: usage,
                                  numberOfNewEntries: numberOfMissingEntries,
                                  isUsed: false)
    }
    
    func generateEntries(for usage: OpalBase.DerivationPath.UsageModel,
                         numberOfNewEntries: Int,
                         isUsed: Bool) async throws {
        guard numberOfNewEntries > 0 else { return }
        
        let currentCount = inventory.countEntries(for: usage)
        let desiredCount = currentCount + numberOfNewEntries
        
        var indices: [UInt32] = .init()
        indices.reserveCapacity(numberOfNewEntries)
        for indexValue in currentCount ..< desiredCount {
            guard let index = UInt32(exactly: indexValue) else { throw Error.indexOutOfBounds }
            indices.append(index)
        }
        
        let newEntries: [EntryModel]
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
            await notifyNewEntry(newEntry)
        }
    }
    
    private func makeEntry(for usage: OpalBase.DerivationPath.UsageModel,
                           index: UInt32,
                           isUsed: Bool) throws -> EntryModel {
        let address = try generateAddress(at: index, for: usage)
        let derivationPath = try createDerivationPath(usage: usage, index: index)
        
        if let existingEntry = inventory.findEntry(for: address) { throw Error.entryDuplicated(existingEntry) }
        
        return EntryModel(address: address,
                     derivationPath: derivationPath,
                     isUsed: isUsed,
                     isReserved: false)
    }
    
    private func makeEntriesUsingUsageDerivationCache(
        usage: OpalBase.DerivationPath.UsageModel,
        indices: [UInt32],
        usageCache: UsageDerivationCache,
        isUsed: Bool
    ) async throws -> [EntryModel] {
        var childPrivateKeys: [Data] = .init()
        childPrivateKeys.reserveCapacity(indices.count)
        var derivationPaths: [OpalBase.DerivationPath] = .init()
        derivationPaths.reserveCapacity(indices.count)
        
        for index in indices {
            let childExtendedPrivateKey = try usageCache.baseExtendedPrivateKey.deriveNonHardenedChildUsingParentKey(
                at: index,
                parentCompressedPublicKey: usageCache.baseCompressedPublicKey,
                parentFingerprint: usageCache.baseFingerprint
            )
            childPrivateKeys.append(childExtendedPrivateKey.privateKey)
            derivationPaths.append(try createDerivationPath(usage: usage, index: index))
        }
        
        let compressedPublicKeys = try await Secp256k1Model.OperationModel.deriveCompressedPublicKeys(
            fromPrivateKeys32: childPrivateKeys,
            assumingValidPrivateKeys: true
        )
        var entries: [EntryModel] = .init()
        entries.reserveCapacity(indices.count)
        
        for (position, compressedPublicKey) in compressedPublicKeys.enumerated() {
            let publicKey = try OpalBase.PublicKey(compressedData: compressedPublicKey)
            let address = try OpalBase.Address(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
            if let existingEntry = inventory.findEntry(for: address) { throw Error.entryDuplicated(existingEntry) }
            
            entries.append(EntryModel(address: address,
                                 derivationPath: derivationPaths[position],
                                 isUsed: isUsed,
                                 isReserved: false))
        }
        
        return entries
    }
}

// MARK: - Get
extension _OpalBase.Address.Book {
    public func selectNextEntry(for usage: OpalBase.DerivationPath.UsageModel) async throws -> EntryModel {
        try await generateEntriesIfNeeded(for: usage)
        
        let entries = inventory.listEntries(for: usage)
        guard let nextEntry = entries.first(where: { !$0.isUsed && !$0.isReserved }) else { throw Error.entryNotFound }
        
        return nextEntry
    }
    
    public func reserveNextEntry(for usage: OpalBase.DerivationPath.UsageModel) async throws -> EntryModel {
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

extension _OpalBase.Address.Book.EntryModel: Sendable {}
extension _OpalBase.Address.Book.EntryModel: Hashable {}
extension _OpalBase.Address.Book.EntryModel: Equatable {}
