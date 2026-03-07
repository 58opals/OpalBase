// TokenMetadataRepository.swift

import Foundation

public actor TokenMetadataRepository {
    private var byCategory: [OpalBase.CashTokens.CategoryIDModel: TokenMetadataModel] = .init()
    
    public init() {}
    
    public func upsert(_ items: [OpalBase.CashTokens.CategoryIDModel: TokenMetadataModel]) {
        for (category, metadata) in items {
            byCategory[category] = makeNormalizedMetadata(metadata, for: category)
        }
    }
    
    public func fetchMetadata(for category: OpalBase.CashTokens.CategoryIDModel) -> TokenMetadataModel? {
        return byCategory[category]
    }
    
    public func snapshot() -> SnapshotModel {
        let snapshotItems = byCategory.reduce(into: [String: TokenMetadataModel]()) { partial, entry in
            partial[entry.key.hexForDisplay] = entry.value
        }
        return SnapshotModel(byCategory: snapshotItems)
    }
    
    public func applySnapshot(_ snapshot: SnapshotModel) {
        byCategory.removeAll(keepingCapacity: true)
        for (hexadecimalString, metadata) in snapshot.byCategory {
            guard let category = try? OpalBase.CashTokens.CategoryIDModel(hexFromRPC: hexadecimalString) else { continue }
            byCategory[category] = makeNormalizedMetadata(metadata, for: category)
        }
    }
    
    public struct SnapshotModel: Codable, Sendable {
        public let byCategory: [String: TokenMetadataModel]
        
        public init(byCategory: [String: TokenMetadataModel]) {
            self.byCategory = byCategory
        }
    }
    
    private func makeNormalizedMetadata(_ metadata: TokenMetadataModel,
                                        for category: OpalBase.CashTokens.CategoryIDModel) -> TokenMetadataModel {
        guard metadata.category != category else { return metadata }
        return TokenMetadataModel(category: category,
                             name: metadata.name,
                             symbol: metadata.symbol,
                             decimals: metadata.decimals,
                             iconURL: metadata.iconURL,
                             lastUpdated: metadata.lastUpdated,
                             source: metadata.source)
    }
}
