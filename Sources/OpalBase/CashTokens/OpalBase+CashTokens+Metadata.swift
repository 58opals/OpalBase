// OpalBase+CashTokens+Metadata.swift

import Foundation

extension _OpalBase.CashTokens {
    public struct Metadata: Codable, Equatable, Sendable {
        public let category: OpalBase.CashTokens.CategoryID
        public let name: String?
        public let symbol: String?
        public let decimals: Int?
        public let iconURL: URL?
        public let lastUpdated: Date
        public let source: Source

        public enum Source: Codable, Equatable, Sendable {
            case embedded
            case dns(URL)
            case chain(OpalBase.Transaction.Hash)
        }

        public init(
            category: OpalBase.CashTokens.CategoryID,
            name: String?,
            symbol: String?,
            decimals: Int?,
            iconURL: URL?,
            lastUpdated: Date,
            source: Source
        ) {
            self.category = category
            self.name = name
            self.symbol = symbol
            self.decimals = decimals
            self.iconURL = iconURL
            self.lastUpdated = lastUpdated
            self.source = source
        }
    }
}
