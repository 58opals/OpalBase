// AddressModel+BookActor+EntryModel.swift

import Foundation
import OpalCrypto

extension AddressModel.BookActor {
    public struct EntryModel {
        public let address: AddressModel
        public let derivationPath: DerivationPathModel
        public let createdAt: Date
        var isUsed: Bool
        var isReserved: Bool
        var cache: Cache
        
        init(address: AddressModel,
             derivationPath: DerivationPathModel,
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
extension AddressModel.BookActor {
    func initializeEntries() async throws {
        for usage in DerivationPathModel.UsageModel.allCases {
            try await generateEntries(for: usage,
                                      numberOfNewEntries: gapLimit,
                                      isUsed: false)
        }
    }
}

// MARK: - Generate
extension AddressModel.BookActor {
    func generateEntriesIfNeeded(for usage: DerivationPathModel.UsageModel) async throws {
        let numberOfRemainingUnusedEntries = inventory.countUnusedEntries(for: usage)
        guard numberOfRemainingUnusedEntries < gapLimit else { return }
        
        let numberOfMissingEntries = gapLimit - numberOfRemainingUnusedEntries
        guard numberOfMissingEntries > 0 else { return }
        
        try await generateEntries(for: usage,
                                  numberOfNewEntries: numberOfMissingEntries,
                                  isUsed: false)
    }
    
    func generateEntries(for usage: DerivationPathModel.UsageModel,
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
    
    private func makeEntry(for usage: DerivationPathModel.UsageModel,
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
        usage: DerivationPathModel.UsageModel,
        indices: [UInt32],
        usageCache: UsageDerivationCache,
        isUsed: Bool
    ) async throws -> [EntryModel] {
        var childPrivateKeys: [Data] = .init()
        childPrivateKeys.reserveCapacity(indices.count)
        var derivationPaths: [DerivationPathModel] = .init()
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
        
        let compressedPublicKeys = try await StandardsForEfficientCryptography256k1CurveModel.OperationModel.deriveCompressedPublicKeys(
            fromPrivateKeys32: childPrivateKeys,
            assumingValidPrivateKeys: true
        )
        var entries: [EntryModel] = .init()
        entries.reserveCapacity(indices.count)
        
        for (position, compressedPublicKey) in compressedPublicKeys.enumerated() {
            let publicKey = try PublicKeyModel(compressedData: compressedPublicKey)
            let address = try AddressModel(script: .p2pkh_OPCHECKSIG(hash: .init(publicKey: publicKey)))
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
extension AddressModel.BookActor {
    public func selectNextEntry(for usage: DerivationPathModel.UsageModel) async throws -> EntryModel {
        try await generateEntriesIfNeeded(for: usage)
        
        let entries = inventory.listEntries(for: usage)
        guard let nextEntry = entries.first(where: { !$0.isUsed && !$0.isReserved }) else { throw Error.entryNotFound }
        
        return nextEntry
    }
    
    public func reserveNextEntry(for usage: DerivationPathModel.UsageModel) async throws -> EntryModel {
        let nextEntry = try await selectNextEntry(for: usage)
        let reservedEntry = try reserveEntry(address: nextEntry.address)
        try await generateEntriesIfNeeded(for: reservedEntry.derivationPath.usage)
        
        return reservedEntry
    }
}

// MARK: - Mark
extension AddressModel.BookActor {
    func checkUsageStatus(of address: AddressModel) throws -> Bool {
        guard let entry = inventory.findEntry(for: address) else { throw Error.addressNotFound }
        return entry.isUsed
    }
    
    func mark(address: AddressModel, isUsed: Bool) async throws {
        let entry = try inventory.mark(address: address, isUsed: isUsed)
        try await generateEntriesIfNeeded(for: entry.derivationPath.usage)
    }
}

extension AddressModel.BookActor.EntryModel: Sendable {}
extension AddressModel.BookActor.EntryModel: Hashable {}
extension AddressModel.BookActor.EntryModel: Equatable {}
