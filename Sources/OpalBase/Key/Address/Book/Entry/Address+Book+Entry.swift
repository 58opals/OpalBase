// Address+Book+Entry.swift

import Foundation
import SwiftFulcrum

extension Address.Book {
    public struct Entry {
        let derivationPath: DerivationPath
        let address: Address
        var isUsed: Bool
        var cache: Cache
        
        init(derivationPath: DerivationPath, address: Address, isUsed: Bool, cache: Cache = .init()) {
            self.derivationPath = derivationPath
            self.address = address
            self.isUsed = isUsed
            self.cache = cache
        }
    }
}

// MARK: - Initialize
extension Address.Book {
    func initializeEntries() throws {
        try generateEntries(for: .receiving,
                            numberOfNewEntries: gapLimit,
                            isUsed: false)
        try generateEntries(for: .change,
                            numberOfNewEntries: gapLimit,
                            isUsed: false)
    }
}

// MARK: - Generate
extension Address.Book {
    func generateEntriesIfNeeded(for usage: DerivationPath.Usage) throws {
        let entries = getEntries(of: usage)
        let usedEntries = getUsedEntries(for: usage)
        
        let numberOfRemainingUnusedEntries = entries.count - usedEntries.count
        if numberOfRemainingUnusedEntries < gapLimit {
            try generateEntries(for: usage,
                                numberOfNewEntries: gapLimit,
                                isUsed: false)
        }
    }
    
    func generateEntries(for usage: DerivationPath.Usage,
                         numberOfNewEntries: Int,
                         isUsed: Bool) throws {
        let entries = getEntries(of: usage)
        let numberOfExistingEntries = entries.count
        
        for _ in numberOfExistingEntries ..< numberOfExistingEntries + numberOfNewEntries {
            try generateEntry(for: usage,
                              isUsed: isUsed)
        }
    }
    
    /// Generates a new entry for the specified usage.
    /// - Parameters:
    ///   - usage: The usage type (`.receiving` or `.change`).
    ///   - isUsed: Indicates wether the address is already used.
    /// - Throws: An error if entry generation fails.
    func generateEntry(for usage: DerivationPath.Usage,
                       isUsed: Bool) throws {
        let nextIndex: UInt32
        
        switch usage {
        case .receiving: nextIndex = UInt32(receivingEntries.count)
        case .change: nextIndex = UInt32(changeEntries.count)
        }
        
        let address = try generateAddress(at: nextIndex, for: usage)
        let derivationPath = try createDerivationPath(usage: usage,
                                                      index: nextIndex)
        
        if let existingEntry = findEntry(for: address) { throw Error.entryDuplicated(existingEntry) }
        
        let newEntry = Entry(derivationPath: derivationPath,
                             address: address,
                             isUsed: isUsed,
                             cache: .init(validityDuration: cacheValidityDuration))
        
        switch usage {
        case .receiving: receivingEntries.append(newEntry)
        case .change: changeEntries.append(newEntry)
        }
        
        addressToEntry[address] = newEntry
        notifyNewEntry(newEntry)
    }
}

// MARK: - Find
extension Address.Book {
    func findEntry(for address: Address) -> Entry? {
        //let allEntries = receivingEntries + changeEntries
        //let entry = allEntries.first(where: { $0.address == address })
        //return entry
        return addressToEntry[address]
    }
}

// MARK: - Get
extension Address.Book {
    public func getNextEntry(for usage: DerivationPath.Usage, fetchBalance: Bool = true) throws -> Entry {
        try generateEntriesIfNeeded(for: usage)
        
        let entries = getEntries(of: usage)
        guard let nextEntry = entries.first(where: { !$0.isUsed }) else { throw Error.entryNotFound }
        
        return nextEntry
    }
    
    public func getEntries(of usage: DerivationPath.Usage) -> [Entry] {
        switch usage {
        case .receiving: return receivingEntries
        case .change: return changeEntries
        }
    }
    
    public func getUsedEntries(for usage: DerivationPath.Usage) -> Set<Entry> {
        let entries = getEntries(of: usage)
        let usedEntries = entries.filter { $0.isUsed }
        return Set<Entry>(usedEntries)
    }
}

// MARK: - Mark
extension Address.Book {
    func isUsed(address: Address) throws -> Bool {
        guard let entry = findEntry(for: address) else { throw Error.addressNotFound }
        return entry.isUsed
    }
    
    func mark(address: Address, isUsed: Bool) throws {
        guard var entry = findEntry(for: address) else { throw Error.addressNotFound }
        entry.isUsed = isUsed
        
        switch entry.derivationPath.usage {
        case .receiving:
            guard let index = receivingEntries.firstIndex(where: { $0.address == address }) else { throw Error.addressNotFound }
            receivingEntries[index].isUsed = isUsed
        case .change:
            guard let index = changeEntries.firstIndex(where: { $0.address == address }) else { throw Error.addressNotFound }
            changeEntries[index].isUsed = isUsed
        }
        
        addressToEntry[address] = entry
        
        try generateEntriesIfNeeded(for: entry.derivationPath.usage)
    }
}

extension Address.Book.Entry: Hashable {}
extension Address.Book.Entry: Sendable {}
