// Address+Book+UsageScan.swift

import Foundation

extension Address.Book {
    public struct UsageScan: Sendable, Equatable {
        public let discoveredUsedEntries: [DerivationPath.Usage: [Entry]]
        public let totalScannedPerUsage: [DerivationPath.Usage: Int]
        
        public init(discoveredUsedEntries: [DerivationPath.Usage: [Entry]],
                    totalScannedPerUsage: [DerivationPath.Usage: Int]) {
            self.discoveredUsedEntries = discoveredUsedEntries
            self.totalScannedPerUsage = totalScannedPerUsage
        }
    }
}

extension Address.Book {
    public func scanForUsedAddresses(using service: Network.AddressReadable,
                                     usage: DerivationPath.Usage? = nil,
                                     includeUnconfirmed: Bool = true) async throws -> UsageScan {
        let targetUsages = DerivationPath.Usage.targets(for: usage)
        var discovered: [DerivationPath.Usage: [Entry]] = .init()
        var scannedCountByUsage: [DerivationPath.Usage: Int] = .init()
        
        for currentUsage in targetUsages {
            var usedEntries: [Entry] = .init()
            var consecutiveUnused = 0
            var currentIndex = 0
            
            while consecutiveUnused < gapLimit {
                let entry = try await loadEntry(at: currentIndex, usage: currentUsage)
                let history = try await service.fetchHistory(for: entry.address.string,
                                                             includeUnconfirmed: includeUnconfirmed)
                
                if history.isEmpty {
                    consecutiveUnused += 1
                } else {
                    consecutiveUnused = 0
                    try await mark(address: entry.address, isUsed: true)
                    
                    if let updatedEntry = findEntry(for: entry.address) {
                        usedEntries.append(updatedEntry)
                    }
                }
                
                currentIndex += 1
            }
            
            discovered[currentUsage] = usedEntries
            scannedCountByUsage[currentUsage] = currentIndex
        }
        
        return UsageScan(discoveredUsedEntries: discovered,
                         totalScannedPerUsage: scannedCountByUsage)
    }
    
    private func loadEntry(at index: Int, usage: DerivationPath.Usage) async throws -> Entry {
        let existingEntries = listEntries(for: usage)
        if index < existingEntries.count {
            return existingEntries[index]
        }
        
        let numberOfMissingEntries = index - existingEntries.count + 1
        try await generateEntries(for: usage,
                                  numberOfNewEntries: numberOfMissingEntries,
                                  isUsed: false)
        let refreshedEntries = listEntries(for: usage)
        
        guard index < refreshedEntries.count else { throw Error.entryNotFound }
        return refreshedEntries[index]
    }
}
