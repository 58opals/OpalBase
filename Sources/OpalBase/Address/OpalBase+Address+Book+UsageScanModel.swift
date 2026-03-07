// OpalBase.Address+BookActor+UsageScanModel.swift

import Foundation

extension _OpalBase.Address.Book {
    public struct UsageScanModel: Sendable, Equatable {
        public let discoveredUsedEntries: [OpalBase.DerivationPath.UsageModel: [EntryModel]]
        public let totalScannedPerUsage: [OpalBase.DerivationPath.UsageModel: Int]
        
        public init(discoveredUsedEntries: [OpalBase.DerivationPath.UsageModel: [EntryModel]],
                    totalScannedPerUsage: [OpalBase.DerivationPath.UsageModel: Int]) {
            self.discoveredUsedEntries = discoveredUsedEntries
            self.totalScannedPerUsage = totalScannedPerUsage
        }
    }
}

extension _OpalBase.Address.Book {
    public func scanForUsedAddresses(using service: OpalBase.Network.AddressReadable,
                                     usage: OpalBase.DerivationPath.UsageModel? = nil,
                                     includeUnconfirmed: Bool = true) async throws -> UsageScanModel {
        let targetUsages = OpalBase.DerivationPath.UsageModel.resolveTargetUsages(for: usage)
        var discovered: [OpalBase.DerivationPath.UsageModel: [EntryModel]] = .init()
        var scannedCountByUsage: [OpalBase.DerivationPath.UsageModel: Int] = .init()
        let batchSize = ConcurrencyModel.Tuning.maximumConcurrentNetworkRequests
        
        for currentUsage in targetUsages {
            var usedEntries: [EntryModel] = .init()
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
        
        return UsageScanModel(discoveredUsedEntries: discovered,
                         totalScannedPerUsage: scannedCountByUsage)
    }
    
    private func checkIfAddressIsUsed(address: String,
                                      using service: OpalBase.Network.AddressReadable,
                                      includeUnconfirmed: Bool) async throws -> Bool {
        let history = try await service.fetchHistory(for: address,
                                                     includeUnconfirmed: includeUnconfirmed)
        return !history.isEmpty
    }
    
    private func loadEntries(for usage: OpalBase.DerivationPath.UsageModel,
                             startIndex: Int,
                             count: Int) async throws -> [EntryModel] {
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
    func performForEachTargetUsage(_ usage: OpalBase.DerivationPath.UsageModel?,
                                   perform action: (OpalBase.DerivationPath.UsageModel, [OpalBase.Address.Book.EntryModel]) async throws -> Void) async rethrows {
        for currentUsage in OpalBase.DerivationPath.UsageModel.resolveTargetUsages(for: usage) {
            let entries = listEntries(for: currentUsage)
            guard !entries.isEmpty else { continue }
            try await action(currentUsage, entries)
        }
    }
}
