// OpalBase+Address+Book+UsageScan.swift

import Foundation

extension _OpalBase.Address.Book {
    struct UsageScan: Sendable, Equatable {
        let discoveredUsedEntries: [OpalBase.Key.DerivationPath.Usage: [Entry]]
        let totalScannedPerUsage: [OpalBase.Key.DerivationPath.Usage: Int]
        
        init(discoveredUsedEntries: [OpalBase.Key.DerivationPath.Usage: [Entry]],
                    totalScannedPerUsage: [OpalBase.Key.DerivationPath.Usage: Int]) {
            self.discoveredUsedEntries = discoveredUsedEntries
            self.totalScannedPerUsage = totalScannedPerUsage
        }
    }
}

extension _OpalBase.Address.Book {
    func scanForUsedAddresses(using service: OpalBase.Network.AddressReader,
                                     usage: OpalBase.Key.DerivationPath.Usage? = nil,
                                     includeUnconfirmed: Bool = true) async throws -> UsageScan {
        let targetUsages = OpalBase.Key.DerivationPath.Usage.resolveTargetUsages(for: usage)
        var discovered: [OpalBase.Key.DerivationPath.Usage: [Entry]] = .init()
        var scannedCountByUsage: [OpalBase.Key.DerivationPath.Usage: Int] = .init()
        let batchSize = 8
        
        for currentUsage in targetUsages {
            var usedEntries: [Entry] = .init()
            var consecutiveUnused = 0
            var currentIndex = 0
            
            while consecutiveUnused < gapLimit {
                let remainingGap = gapLimit - consecutiveUnused
                let queryCount = Swift.min(batchSize, remainingGap)
                let entries = try await loadEntries(for: currentUsage,
                                                    startIndex: currentIndex,
                                                    count: queryCount)
                guard !entries.isEmpty else { break }
                
                let usageResults = try await entries.mapConcurrently { entry in
                    try await self.isAddressUsed(entry.address.string,
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

    func scanForUsedAddresses(using service: any OpalBase.Network.AddressReadable,
                              usage: OpalBase.Key.DerivationPath.Usage? = nil,
                              includeUnconfirmed: Bool = true) async throws -> UsageScan {
        try await scanForUsedAddresses(using: .init(service),
                                       usage: usage,
                                       includeUnconfirmed: includeUnconfirmed)
    }
    
    private func isAddressUsed(_ address: String,
                               using service: OpalBase.Network.AddressReader,
                               includeUnconfirmed: Bool) async throws -> Bool {
        let history = try await service.fetchHistory(for: address,
                                                     includeUnconfirmed: includeUnconfirmed)
        return !history.isEmpty
    }
    
    private func loadEntries(for usage: OpalBase.Key.DerivationPath.Usage,
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
        guard startIndex < safeEndIndex else { return .init() }
        return Array(refreshedEntries[startIndex..<safeEndIndex])
    }
}

extension _OpalBase.Address.Book {
    func performForEachTargetUsage(_ usage: OpalBase.Key.DerivationPath.Usage?,
                                   perform action: (OpalBase.Key.DerivationPath.Usage, [OpalBase.Address.Book.Entry]) async throws -> Void) async rethrows {
        for currentUsage in OpalBase.Key.DerivationPath.Usage.resolveTargetUsages(for: usage) {
            let entries = listEntries(for: currentUsage)
            guard !entries.isEmpty else { continue }
            try await action(currentUsage, entries)
        }
    }
}
