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

extension Address.Book {
    func updateCache(for address: Address,
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
