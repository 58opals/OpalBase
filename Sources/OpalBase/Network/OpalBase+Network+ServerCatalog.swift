// OpalBase+Network+ServerCatalog.swift

import Foundation

extension _OpalBase.Network {
    public struct ServerCatalog: Sendable, Equatable {
        private var normalizedMainnetServers: [URL]
        private var normalizedChipnetServers: [URL]
        private var normalizedTestnetServers: [URL]

        public var mainnetServers: [URL] {
            get { normalizedMainnetServers }
            set { normalizedMainnetServers = Self.makeNormalizedServers(newValue) }
        }
        public var chipnetServers: [URL] {
            get { normalizedChipnetServers }
            set { normalizedChipnetServers = Self.makeNormalizedServers(newValue) }
        }
        public var testnetServers: [URL] {
            get { normalizedTestnetServers }
            set { normalizedTestnetServers = Self.makeNormalizedServers(newValue) }
        }
        
        public init(
            mainnetServers: [URL] = Self.defaultMainnetServers,
            chipnetServers: [URL] = Self.defaultChipnetServers,
            testnetServers: [URL] = Self.defaultTestnetServers
        ) {
            self.normalizedMainnetServers = Self.makeNormalizedServers(mainnetServers)
            self.normalizedChipnetServers = Self.makeNormalizedServers(chipnetServers)
            self.normalizedTestnetServers = Self.makeNormalizedServers(testnetServers)
        }
        
        public func listServers(for environment: OpalBase.Network.Environment) -> [URL] {
            switch environment {
            case .mainnet:
                return mainnetServers
            case .chipnet:
                return chipnetServers
            case .testnet:
                return testnetServers
            }
        }
    }
}

extension _OpalBase.Network.ServerCatalog {
    public static let opalDefault = Self()
    
    static func makeMergedServers(primary: [URL], fallback: [URL]) -> [URL] {
        makeNormalizedServers(primary + fallback)
    }
    
    static func makeNormalizedServers(_ servers: [URL]) -> [URL] {
        var seen = Set<String>()
        var normalizedServers: [URL] = .init()
        normalizedServers.reserveCapacity(servers.count)
        
        for server in servers {
            guard let normalizedServer = makeNormalizedServer(server) else { continue }
            let key = normalizedServer.absoluteString
            if seen.insert(key).inserted {
                normalizedServers.append(normalizedServer)
            }
        }
        
        return normalizedServers
    }
}

extension _OpalBase.Network.ServerCatalog {
    public static let defaultMainnetServers: [URL] = [
        URL(string: "wss://bch.imaginary.cash:50004")!,
        URL(string: "wss://bch.loping.net:50004")!,
        URL(string: "wss://fulcrum.greyh.at:50004")!,
        URL(string: "wss://cashnode.bch.ninja:50004")!,
        URL(string: "wss://electrum.imaginary.cash:50004")!,
        URL(string: "wss://electroncash.dk:50004")!
    ]
    
    public static let defaultChipnetServers: [URL] = [
        URL(string: "wss://chipnet.imaginary.cash:50004")!
    ]
    
    public static let defaultTestnetServers: [URL] = [
        URL(string: "wss://testnet.imaginary.cash:50004")!,
        URL(string: "wss://testnet.bch.loping.net:51004")!
    ]
    
    static func makeNormalizedServer(_ server: URL) -> URL? {
        guard var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else {
            return nil
        }
        
        guard let rawScheme = components.scheme?.lowercased() else {
            return nil
        }

        guard let host = components.host,
              host.isEmpty == false,
              !isInvalidHost(host) else {
            return nil
        }
        components.host = host.lowercased()

        guard components.user == nil, components.password == nil else {
            return nil
        }
        
        if let port = components.port, !(1...65_535).contains(port) {
            return nil
        }

        guard !URLPathTraversal.containsPathTraversal(inPath: components.path) else {
            return nil
        }
        
        let normalizedScheme: String
        switch rawScheme {
        case "wss", "ws":
            normalizedScheme = rawScheme
        case "https":
            normalizedScheme = "wss"
        case "http":
            normalizedScheme = "ws"
        default:
            return nil
        }
        
        components.scheme = normalizedScheme
        if components.port == defaultPort(for: normalizedScheme) {
            components.port = nil
        }
        if components.path == "/" {
            components.path = ""
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func isInvalidHost(_ host: String) -> Bool {
        if host.contains(":") {
            return !URLHostValidation.isValidBracketedInternetProtocolLiteral(host)
        }
        return !URLHostValidation.isValidDomainName(host)
    }

    private static func defaultPort(for normalizedScheme: String) -> Int? {
        switch normalizedScheme {
        case "wss":
            return 443
        case "ws":
            return 80
        default:
            return nil
        }
    }
}
