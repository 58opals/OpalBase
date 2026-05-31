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
            self.decimals = decimals.flatMap { $0 >= 0 ? $0 : nil }
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
              Self.isValidMetadataPort(url.port),
              url.user == nil,
              url.password == nil
        else { return nil }
        let pathComponents = url.path.split(separator: "/")
        switch scheme {
        case "https":
            guard let host = url.host,
                  !host.isEmpty,
                  !Self.isPathTraversalComponent(host),
                  !Self.containsPathTraversal(in: pathComponents)
            else { return nil }
        case "ipfs":
            if let host = url.host {
                guard !Self.isPathTraversalComponent(host) else { return nil }
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

    private static func isPathTraversalComponent(_ component: some StringProtocol) -> Bool {
        var currentComponent = String(component)
        while true {
            if currentComponent == "." || currentComponent == ".." {
                return true
            }
            guard let decodedComponent = currentComponent.removingPercentEncoding,
                  decodedComponent != currentComponent else {
                return false
            }
            currentComponent = decodedComponent
        }
    }

    private static func containsPathTraversal(in pathComponents: [String.SubSequence]) -> Bool {
        pathComponents.contains(where: Self.isPathTraversalComponent)
    }
}
