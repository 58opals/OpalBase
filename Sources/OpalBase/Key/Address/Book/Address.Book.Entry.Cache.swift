import Foundation
import SwiftFulcrum

extension Address.Book.Entry {
    struct Cache {
        var balance: Satoshi?
        var lastUpdated: Date?
        let validityDuration: TimeInterval = 60 * 10
        
        var isValid: Bool { if let lastUpdated { return (Date().timeIntervalSince(lastUpdated) < validityDuration) } else { return false } }
    }
}

extension Address.Book.Entry {
    mutating func getBalance(using fulcrum: Fulcrum) async throws -> Satoshi {
        if cache.isValid, let cacheBalance = cache.balance {
            return cacheBalance
        } else {
            try await fetchBalance(using: fulcrum)
            guard cache.isValid else { throw Address.Book.Error.cacheInvalid }
            guard let fetchedBalance = cache.balance else { throw Address.Book.Error.cacheUpdateFailed }
            return fetchedBalance
        }
    }
}

extension Address.Book {
    public mutating func updateCache(using fulcrum: Fulcrum) async throws {
        try await updateCache(in: receivingEntries, fulcrum: fulcrum)
        try await updateCache(in: changeEntries, fulcrum: fulcrum)
    }
    
    mutating func updateCache(in entries: [Entry], fulcrum: Fulcrum) async throws {
        for entry in entries where !entry.cache.isValid {
            let address = entry.address
            let latestBalance = try await address.fetchBalance(using: fulcrum)
            try updateCache(for: address, with: latestBalance)
        }
    }
    
    mutating func updateCache(for address: Address,
                              with balance: Satoshi) throws {
        guard let existingEntry = findEntry(for: address) else { throw Error.entryNotFound }
        
        let newCache = Entry.Cache(balance: balance)
        let newEntry = Entry(derivationPath: existingEntry.derivationPath,
                             address: address,
                             isUsed: existingEntry.isUsed,
                             cache: newCache)
        
        switch existingEntry.derivationPath.usage {
        case .receiving:
            guard let index = receivingEntries.firstIndex(where: { $0.address == address }) else { throw Error.entryNotFound }
            receivingEntries[index] = newEntry
        case .change:
            guard let index = changeEntries.firstIndex(where: { $0.address == address }) else { throw Error.entryNotFound }
            changeEntries[index] = newEntry
        }
    }
}

extension Address.Book.Entry.Cache: Hashable {}
