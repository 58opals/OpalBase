// TokenMetadataStore.swift

import Foundation

public actor TokenMetadataStore {
    private var byCategory: [CashTokens.CategoryID: TokenMetadata] = .init()
    
    public init() {}
    
    public func upsert(_ items: [CashTokens.CategoryID: TokenMetadata]) {
        for (category, metadata) in items {
            byCategory[category] = makeNormalizedMetadata(metadata, for: category)
        }
    }
    
    public func fetchMetadata(for category: CashTokens.CategoryID) -> TokenMetadata? {
        return byCategory[category]
    }
    
    public func snapshot() -> Snapshot {
        let snapshotItems = byCategory.reduce(into: [String: TokenMetadata]()) { partial, entry in
            partial[entry.key.hexForDisplay] = entry.value
        }
        return Snapshot(byCategory: snapshotItems)
    }
    
    public func applySnapshot(_ snapshot: Snapshot) {
        byCategory.removeAll(keepingCapacity: true)
        for (hexadecimalString, metadata) in snapshot.byCategory {
            guard let category = try? CashTokens.CategoryID(hexFromRPC: hexadecimalString) else { continue }
            byCategory[category] = makeNormalizedMetadata(metadata, for: category)
        }
    }
    
    public struct Snapshot: Codable, Sendable {
        public let byCategory: [String: TokenMetadata]
        
        public init(byCategory: [String: TokenMetadata]) {
            self.byCategory = byCategory
        }
    }
    
    private func makeNormalizedMetadata(_ metadata: TokenMetadata,
                                        for category: CashTokens.CategoryID) -> TokenMetadata {
        guard metadata.category != category else { return metadata }
        return TokenMetadata(category: category,
                             name: metadata.name,
                             symbol: metadata.symbol,
                             decimals: metadata.decimals,
                             iconURL: metadata.iconURL,
                             lastUpdated: metadata.lastUpdated,
                             source: metadata.source)
    }
}
