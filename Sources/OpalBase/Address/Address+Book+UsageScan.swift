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
        let batchSize = Concurrency.Tuning.maximumConcurrentNetworkRequests
        
        for currentUsage in targetUsages {
            var usedEntries: [Entry] = .init()
            var consecutiveUnused = 0
            var currentIndex = 0
            
            while consecutiveUnused < gapLimit {
                let entries = try await loadEntries(for: currentUsage,
                                                    startIndex: currentIndex,
                                                    count: batchSize)
                guard !entries.isEmpty else { break }
                
                let usageResults = try await entries.mapConcurrently { entry in
                    try await self.checkIfAddressIsUsed(address: entry.address.string,
                                                        using: service,
                                                        includeUnconfirmed: includeUnconfirmed)
                }
                
                for (entry, isUsed) in zip(entries, usageResults) {
                    guard consecutiveUnused < gapLimit else { break }
                    
                    if isUsed {
                        consecutiveUnused = 0
                        try await mark(address: entry.address, isUsed: true)
                        
                        if let updatedEntry = findEntry(for: entry.address) {
                            usedEntries.append(updatedEntry)
                        }
                    } else {
                        consecutiveUnused += 1
                    }
                    
                    currentIndex += 1
                }
            }
            
            discovered[currentUsage] = usedEntries
            scannedCountByUsage[currentUsage] = currentIndex
        }
        
        return UsageScan(discoveredUsedEntries: discovered,
                         totalScannedPerUsage: scannedCountByUsage)
    }
    
    private func checkIfAddressIsUsed(address: String,
                                      using service: Network.AddressReadable,
                                      includeUnconfirmed: Bool) async throws -> Bool {
        let history = try await service.fetchHistory(for: address,
                                                     includeUnconfirmed: includeUnconfirmed)
        return !history.isEmpty
    }
    
    private func loadEntries(for usage: DerivationPath.Usage,
                             startIndex: Int,
                             count: Int) async throws -> [Entry] {
        let endIndex = startIndex + count
        let existingEntries = listEntries(for: usage)
        if endIndex <= existingEntries.count {
            return Array(existingEntries[startIndex..<endIndex])
        }
        
        let numberOfMissingEntries = endIndex - existingEntries.count
        if numberOfMissingEntries > 0 {
            try await generateEntries(for: usage,
                                      numberOfNewEntries: numberOfMissingEntries,
                                      isUsed: false)
        }
        
        let refreshedEntries = listEntries(for: usage)
        let safeEndIndex = Swift.min(endIndex, refreshedEntries.count)
        guard startIndex < safeEndIndex else { return [] }
        return Array(refreshedEntries[startIndex..<safeEndIndex])
    }
}

extension Address.Book {
    func forEachTargetUsage(_ usage: DerivationPath.Usage?,
                            perform action: (DerivationPath.Usage, [Address.Book.Entry]) async throws -> Void) async rethrows {
        for currentUsage in DerivationPath.Usage.targets(for: usage) {
            let entries = listEntries(for: currentUsage)
            guard !entries.isEmpty else { continue }
            try await action(currentUsage, entries)
        }
    }
}
