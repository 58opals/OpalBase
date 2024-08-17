import Foundation

extension Address.Book.Entry {
    struct Cache {
        var balance: Satoshi
        var lastUpdated: Date = Date()
        let validityDuration: TimeInterval = 60 * 10
        
        var isValid: Bool { Date().timeIntervalSince(lastUpdated) < validityDuration }
    }
}

extension Address.Book.Entry.Cache: Hashable {}

extension Address.Book {
    mutating func updateCache(in entries: [Entry]) async throws {
        for entry in entries where !entry.cache.isValid {
            let address = entry.address
            let latestBalance = try await address.fetchBalance(using: fulcrum)
            try updateCache(for: address, with: latestBalance)
        }
    }
    
    mutating func updateCache(for address: Address,
                              with balance: Satoshi) throws {
        guard let existingEntry = findEntry(for: address) else { throw Error.entryNotFound }
        
        let newCache = Entry.Cache(balance: balance,
                                   lastUpdated: Date())
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

