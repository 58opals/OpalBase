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

        private enum CodingKeys: String, CodingKey {
            case category
            case name
            case symbol
            case decimals
            case iconURL
            case description
            case webURL
            case identity
            case authbase
            case registryURL
            case lastUpdated
            case source
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
            self.decimals = decimals.flatMap { $0 >= 0 ? $0 : nil }
            self.iconURL = Self.makeSafeMetadataURL(iconURL)
            self.description = description
            self.webURL = Self.makeSafeMetadataURL(webURL)
            self.identity = identity
            self.authbase = authbase
            self.registryURL = Self.makeSafeMetadataURL(registryURL)
            self.lastUpdated = lastUpdated
            switch source {
            case .dns(let url):
                self.source = Self.makeSafeMetadataURL(url).map(Source.dns) ?? .embedded
            case .embedded, .chain:
                self.source = source
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                category: container.decode(OpalBase.CashTokens.CategoryID.self, forKey: .category),
                name: container.decodeIfPresent(String.self, forKey: .name),
                symbol: container.decodeIfPresent(String.self, forKey: .symbol),
                decimals: container.decodeIfPresent(Int.self, forKey: .decimals),
                iconURL: container.decodeIfPresent(URL.self, forKey: .iconURL),
                lastUpdated: container.decode(Date.self, forKey: .lastUpdated),
                source: container.decode(Source.self, forKey: .source),
                description: container.decodeIfPresent(String.self, forKey: .description),
                webURL: container.decodeIfPresent(URL.self, forKey: .webURL),
                identity: container.decodeIfPresent(String.self, forKey: .identity),
                authbase: container.decodeIfPresent(OpalBase.Transaction.Hash.self, forKey: .authbase),
                registryURL: container.decodeIfPresent(URL.self, forKey: .registryURL)
            )
        }
    }
}

extension _OpalBase.CashTokens.Metadata {
    static func makeSafeMetadataURL(_ url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              Self.isValidMetadataPort(url.port),
              url.user == nil,
              url.password == nil
        else { return nil }
        let pathComponents = url.path.split(separator: "/")
        switch scheme {
        case "https":
            guard let host = url.host,
                  !host.isEmpty,
                  Self.isValidMetadataHost(host),
                  !Self.containsPathTraversal(in: pathComponents)
            else { return nil }
        case "ipfs":
            if let host = url.host {
                guard Self.isValidMetadataHost(host) else { return nil }
            }
            guard !Self.containsPathTraversal(in: pathComponents),
                  url.host != nil || !pathComponents.isEmpty else { return nil }
        default:
            return nil
        }
        return url
    }

    private static func isValidMetadataPort(_ port: Int?) -> Bool {
        guard let port else { return true }
        return (1...65_535).contains(port)
    }

    private static func containsPathTraversal(in pathComponents: [String.SubSequence]) -> Bool {
        URLPathTraversal.containsPathTraversal(pathComponents.map(String.init))
    }

    private static func isValidMetadataHost(_ host: String) -> Bool {
        guard !URLPathTraversal.isPathTraversalComponent(host) else {
            return false
        }
        return URLHostValidation.isValidUnbracketedHostLiteralOrName(host)
    }
}
