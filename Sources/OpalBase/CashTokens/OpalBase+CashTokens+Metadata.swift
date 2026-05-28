// OpalBase+CashTokens+Metadata.swift

import Foundation

extension _OpalBase.CashTokens {
    public struct Metadata: Codable, Equatable, Sendable {
        public let category: OpalBase.CashTokens.CategoryID
        public let name: String?
        public let symbol: String?
        public let decimals: Int?
        public let iconURL: URL?
        public let description: String?
        public let webURL: URL?
        public let identity: String?
        public let authbase: OpalBase.Transaction.Hash?
        public let registryURL: URL?
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
            source: Source,
            description: String? = nil,
            webURL: URL? = nil,
            identity: String? = nil,
            authbase: OpalBase.Transaction.Hash? = nil,
            registryURL: URL? = nil
        ) {
            self.category = category
            self.name = name
            self.symbol = symbol
            self.decimals = decimals
            self.iconURL = iconURL
            self.description = description
            self.webURL = webURL
            self.identity = identity
            self.authbase = authbase
            self.registryURL = registryURL
            self.lastUpdated = lastUpdated
            self.source = source
        }
    }
}

extension _OpalBase.CashTokens.Metadata {
    static func makeSafeMetadataURL(_ url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              url.user == nil,
              url.password == nil
        else { return nil }
        switch scheme {
        case "https":
            guard let host = url.host, !host.isEmpty else { return nil }
        case "ipfs":
            guard url.host != nil || !url.path.split(separator: "/").isEmpty else { return nil }
        default:
            return nil
        }
        return url
    }
}
