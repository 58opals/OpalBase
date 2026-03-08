// OpalBase+CashTokens+MetadataRepository.swift

import Foundation

extension _OpalBase.CashTokens {
    public actor MetadataRepository {
        private var byCategory: [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata] = .init()

        public init() {}

        public func upsert(_ items: [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata]) {
            for (category, metadata) in items {
                byCategory[category] = makeNormalizedMetadata(metadata, for: category)
            }
        }

        public func fetchMetadata(for category: OpalBase.CashTokens.CategoryID) -> OpalBase.CashTokens.Metadata? {
            byCategory[category]
        }

        public func snapshot() -> Snapshot {
            let snapshotItems = byCategory.reduce(into: [String: OpalBase.CashTokens.Metadata]()) { partial, entry in
                partial[entry.key.hexForDisplay] = entry.value
            }
            return Snapshot(byCategory: snapshotItems)
        }

        public func applySnapshot(_ snapshot: Snapshot) {
            byCategory.removeAll(keepingCapacity: true)
            for (hexadecimalString, metadata) in snapshot.byCategory {
                guard let category = try? OpalBase.CashTokens.CategoryID(hexFromRPC: hexadecimalString) else { continue }
                byCategory[category] = makeNormalizedMetadata(metadata, for: category)
            }
        }

        public struct Snapshot: Codable, Sendable {
            public let byCategory: [String: OpalBase.CashTokens.Metadata]

            public init(byCategory: [String: OpalBase.CashTokens.Metadata]) {
                self.byCategory = byCategory
            }
        }

        private func makeNormalizedMetadata(
            _ metadata: OpalBase.CashTokens.Metadata,
            for category: OpalBase.CashTokens.CategoryID
        ) -> OpalBase.CashTokens.Metadata {
            guard metadata.category != category else { return metadata }
            return OpalBase.CashTokens.Metadata(
                category: category,
                name: metadata.name,
                symbol: metadata.symbol,
                decimals: metadata.decimals,
                iconURL: metadata.iconURL,
                lastUpdated: metadata.lastUpdated,
                source: metadata.source
            )
        }
    }
}
