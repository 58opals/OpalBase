import Foundation
import SwiftFulcrum

extension Address.Book {
    public struct Entry {
        let derivationPath: DerivationPath
        let address: Address
        var isUsed: Bool
        var cache: Cache
    }
}

extension Address.Book.Entry: Hashable {}

// MARK: - Get
extension Address.Book {
    public func findEntry(for address: Address) -> Entry? {
        let allEntries = receivingEntries + changeEntries
        let entry = allEntries.first(where: { $0.address == address })
        return entry
    }
    
    public mutating func getNextEntry(for usage: DerivationPath.Usage, fulcrum: Fulcrum) async throws -> Entry {
        try await generateEntriesIfNeeded(for: usage, fulcrum: fulcrum)
        
        let entries = getEntries(of: usage)
        guard let nextEntry = entries.first(where: { !$0.isUsed }) else { throw Error.entryNotFound }
        
        return nextEntry
    }
    
    private func getUsedEntries(for usage: DerivationPath.Usage) -> Set<Entry> {
        let entries = getEntries(of: usage)
        let usedEntries = entries.filter { $0.isUsed }
        return Set<Entry>(usedEntries)
    }
    
    private func getEntries(of usage: DerivationPath.Usage) -> [Entry] {
        switch usage {
        case .receiving: return receivingEntries
        case .change: return changeEntries
        }
    }
}

// MARK: - Set
extension Address.Book {
    mutating func initializeEntries(fulcrum: Fulcrum) async throws {
        try await generateEntries(for: .receiving,
                                  isUsed: false,
                                  fetchBalance: true,
                                  numberOfNewEntries: gapLimit,
                                  fulcrum: fulcrum)
        try await generateEntries(for: .change,
                                  isUsed: false,
                                  fetchBalance: true,
                                  numberOfNewEntries: gapLimit,
                                  fulcrum: fulcrum)
    }
}

extension Address.Book {
    mutating func generateEntriesIfNeeded(for usage: DerivationPath.Usage, fulcrum: Fulcrum) async throws {
        let entries = getEntries(of: usage)
        let usedEntries = getUsedEntries(for: usage)
        
        let numberOfRemainingUnusedEntries = entries.count - usedEntries.count
        if numberOfRemainingUnusedEntries <= gapLimit {
            try await generateEntries(for: usage, numberOfNewEntries: gapLimit, fulcrum: fulcrum)
        }
    }
    
    mutating func generateEntries(for usage: DerivationPath.Usage,
                                  isUsed: Bool = false,
                                  fetchBalance: Bool = true,
                                  numberOfNewEntries: Int,
                                  fulcrum: Fulcrum) async throws {
        let entries = getEntries(of: usage)
        
        for index in (entries.count) ..< (entries.count + numberOfNewEntries) {
            try await generateEntry(for: usage, at: UInt32(index), isUsed: isUsed, fetchBalance: fetchBalance, fulcrum: fulcrum)
        }
    }
    
    private mutating func generateEntry(for usage: DerivationPath.Usage,
                                        at index: UInt32,
                                        isUsed: Bool = false,
                                        fetchBalance: Bool = true,
                                        fulcrum: Fulcrum) async throws {
        let address = try generateAddress(at: index, for: usage)
        let balance = try fetchBalance ? await address.fetchBalance(using: fulcrum) : .init(0)
        
        let newEntry = try Entry(derivationPath: createDerivationPath(usage: usage, index: index),
                                 address: address,
                                 isUsed: isUsed,
                                 cache: .init(balance: balance))
        
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

// MARK: - Mark
extension Address.Book {
    func isUsed(address: Address) throws -> Bool {
        guard let entry = findEntry(for: address) else { throw Error.addressNotFound }
        return entry.isUsed
    }
    
    mutating func mark(address: Address, isUsed: Bool, fulcrum: Fulcrum) async throws {
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
        
        try await generateEntriesIfNeeded(for: usage, fulcrum: fulcrum)
    }
    
    public mutating func refreshUsedStatus(fulcrum: Fulcrum) async throws {
        try await refreshUsedStatus(for: .receiving, fulcrum: fulcrum)
        try await refreshUsedStatus(for: .change, fulcrum: fulcrum)
    }
    
    mutating func refreshUsedStatus(for usage: DerivationPath.Usage, fulcrum: Fulcrum) async throws {
        let entries = getEntries(of: usage)
        for (index, entry) in entries.enumerated() {
            let transactionHistory = try await entry.address.fetchUnspentTransactionOutputs(fulcrum: fulcrum)
            if !transactionHistory.isEmpty {
                switch usage {
                case .receiving: receivingEntries[index].isUsed = true
                case .change: changeEntries[index].isUsed = true
                }
            }
        }
    }
}
