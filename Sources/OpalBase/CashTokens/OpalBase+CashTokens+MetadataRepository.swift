// OpalBase+CashTokens+MetadataRepository.swift

import Foundation

extension _OpalBase.CashTokens {
    public actor MetadataRepository {
        private static let safeMetadataURLSchemes: Set<String> = ["https", "ipfs"]
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
            return OpalBase.CashTokens.Metadata(
                category: category,
                name: metadata.name,
                symbol: metadata.symbol,
                decimals: metadata.decimals,
                iconURL: makeSafeURL(metadata.iconURL),
                lastUpdated: metadata.lastUpdated,
                source: makeSafeSource(metadata.source),
                description: metadata.description,
                webURL: makeSafeURL(metadata.webURL),
                identity: metadata.identity,
                authbase: metadata.authbase,
                registryURL: makeSafeURL(metadata.registryURL)
            )
        }

        private func makeSafeURL(_ url: URL?) -> URL? {
            guard let url,
                  let scheme = url.scheme?.lowercased(),
                  Self.safeMetadataURLSchemes.contains(scheme),
                  let host = url.host,
                  !host.isEmpty
            else { return nil }
            return url
        }

        private func makeSafeSource(_ source: OpalBase.CashTokens.Metadata.Source) -> OpalBase.CashTokens.Metadata.Source {
            switch source {
            case .dns(let url):
                guard let safeURL = makeSafeURL(url) else { return .embedded }
                return .dns(safeURL)
            case .embedded, .chain:
                return source
            }
        }
    }
}
