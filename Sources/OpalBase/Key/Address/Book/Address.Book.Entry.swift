import Foundation
import SwiftFulcrum

extension Address.Book {
    public struct Entry {
        let derivationPath: DerivationPath
        public let address: Address
        public var isUsed: Bool
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
    mutating func initializeEntries() throws {
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
    mutating func generateEntriesIfNeeded(for usage: DerivationPath.Usage) throws {
        let entries = getEntries(of: usage)
        let usedEntries = getUsedEntries(for: usage)
        
        let numberOfRemainingUnusedEntries = entries.count - usedEntries.count
        if numberOfRemainingUnusedEntries <= gapLimit {
            try generateEntries(for: usage,
                                numberOfNewEntries: gapLimit,
                                isUsed: false)
        }
    }
    
    public mutating func generateEntries(for usage: DerivationPath.Usage,
                         numberOfNewEntries: Int,
                         isUsed: Bool) throws {
        let entries = getEntries(of: usage)
        let numberOfExistingEntries = entries.count
        
        for index in numberOfExistingEntries ..< numberOfExistingEntries + numberOfNewEntries {
            try generateEntry(for: usage,
                              at: UInt32(index),
                              isUsed: isUsed)
        }
    }
    
    mutating func generateEntry(for usage: DerivationPath.Usage,
                       at index: UInt32,
                       isUsed: Bool) throws {
        let address = try generateAddress(at: index, for: usage)
        let derivationPath = try createDerivationPath(usage: usage,
                                                      index: UInt32(index))
        let newEntry = Entry(derivationPath: derivationPath,
                             address: address,
                             isUsed: isUsed)
        
        switch usage {
        case .receiving:
            if receivingEntries.count <= index { receivingEntries.append(newEntry) }
            else { receivingEntries[Int(index)] = newEntry }
        case .change:
            if changeEntries.count <= index { changeEntries.append(newEntry) }
            else { changeEntries[Int(index)] = newEntry }
        }
    }
}

// MARK: - Find
extension Address.Book {
    public func findEntry(for address: Address) -> Entry? {
        let allEntries = receivingEntries + changeEntries
        let entry = allEntries.first(where: { $0.address == address })
        return entry
    }
}

// MARK: - Get
extension Address.Book {
    public mutating func getNextEntry(for usage: DerivationPath.Usage, fetchBalance: Bool = true) throws -> Entry {
        try generateEntriesIfNeeded(for: usage)
        
        let entries = getEntries(of: usage)
        guard let nextEntry = entries.first(where: { !$0.isUsed }) else { throw Error.entryNotFound }
        
        return nextEntry
    }
    
    private func getEntries(of usage: DerivationPath.Usage) -> [Entry] {
        switch usage {
        case .receiving: return receivingEntries
        case .change: return changeEntries
        }
    }
    
    private func getUsedEntries(for usage: DerivationPath.Usage) -> Set<Entry> {
        let entries = getEntries(of: usage)
        let usedEntries = entries.filter { $0.isUsed }
        return Set<Entry>(usedEntries)
    }
}

// MARK: - Mark
extension Address.Book {
    public func isUsed(address: Address) throws -> Bool {
        guard let entry = findEntry(for: address) else { throw Error.addressNotFound }
        return entry.isUsed
    }
    
    public mutating func mark(address: Address, isUsed: Bool) throws {
        let numberOfReceivingAddresses = receivingEntries.filter { $0.address == address }.count
        let numberOfChangeAddresses = changeEntries.filter { $0.address == address }.count
        
        var usage: DerivationPath.Usage?
        
        if (numberOfReceivingAddresses + numberOfChangeAddresses) == 0 { throw Error.addressNotFound }
        else if (numberOfReceivingAddresses == 1 && numberOfChangeAddresses == 0) { usage = .receiving }
        else if (numberOfReceivingAddresses == 0 && numberOfChangeAddresses == 1) { usage = .change }
        else { throw Error.addressDuplicated}
        
        guard let usage = usage else { throw Error.addressNotFound }
        
        switch usage {
        case .receiving:
            guard let index = receivingEntries.firstIndex(where: { $0.address == address }) else { throw Error.addressNotFound }
            receivingEntries[index].isUsed = isUsed
        case .change:
            guard let index = changeEntries.firstIndex(where: { $0.address == address }) else { throw Error.addressNotFound }
            changeEntries[index].isUsed = isUsed
        }
        
        try generateEntriesIfNeeded(for: usage)
    }
}



// MARK: - Refresh
extension Address.Book {
    public mutating func refreshUsedStatus(fulcrum: Fulcrum) async throws {
        try await refreshUsedStatus(for: .receiving, fulcrum: fulcrum)
        try await refreshUsedStatus(for: .change, fulcrum: fulcrum)
    }
    
    mutating func refreshUsedStatus(for usage: DerivationPath.Usage, fulcrum: Fulcrum) async throws {
        let entries = getEntries(of: usage)
        
        for entry in entries {
            if entry.isUsed { continue }
            
            if let cacheBalance = entry.cache.balance {
                if cacheBalance.uint64 > 0 {
                    let unspentTransactionOutputs = try await entry.address.fetchUnspentTransactionOutputs(fulcrum: fulcrum)
                    if !unspentTransactionOutputs.isEmpty {
                        try mark(address: entry.address, isUsed: true)
                    }
                } else if cacheBalance.uint64 == 0 {
                    let transactionHistory = try await entry.address.fetchTransactionHistory(fulcrum: fulcrum)
                    if !transactionHistory.isEmpty {
                        try mark(address: entry.address, isUsed: true)
                    }
                }
            }
        }
    }
}

// MARK: -
extension Address.Book.Entry: Hashable {}
