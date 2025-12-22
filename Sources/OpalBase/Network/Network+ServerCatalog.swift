// Network+ServerCatalog.swift

import Foundation

extension Network {
    public struct ServerCatalog: Sendable, Equatable {
        public var mainnetServers: [URL]
        public var chipnetServers: [URL]
        public var testnetServers: [URL]
        
        public init(
            mainnetServers: [URL] = Self.defaultMainnetServers,
            chipnetServers: [URL] = Self.defaultChipnetServers,
            testnetServers: [URL] = Self.defaultTestnetServers
        ) {
            self.mainnetServers = Self.makeNormalizedServers(mainnetServers)
            self.chipnetServers = Self.makeNormalizedServers(chipnetServers)
            self.testnetServers = Self.makeNormalizedServers(testnetServers)
        }
        
        public func servers(for environment: Network.Environment) -> [URL] {
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

extension Network.ServerCatalog {
    public static let opalDefault = Self()
    
    static func makeMergedServers(primary: [URL], secondary: [URL], fallback: [URL]) -> [URL] {
        let normalizedFallback = makeNormalizedServers(fallback)
        let merged = primary + secondary + normalizedFallback
        var seen = Set<String>()
        var uniqueServers: [URL] = .init()
        uniqueServers.reserveCapacity(merged.count)
        
        for server in merged {
            let key = server.absoluteString.lowercased()
            if seen.insert(key).inserted {
                uniqueServers.append(server)
            }
        }
        
        return uniqueServers
    }
    
    static func makeNormalizedServers(_ servers: [URL]) -> [URL] {
        var seen = Set<String>()
        var normalizedServers: [URL] = .init()
        normalizedServers.reserveCapacity(servers.count)
        
        for server in servers {
            guard let normalizedServer = makeNormalizedServer(server) else { continue }
            let key = normalizedServer.absoluteString.lowercased()
            if seen.insert(key).inserted {
                normalizedServers.append(normalizedServer)
            }
        }
        
        return normalizedServers
    }
}

extension Network.ServerCatalog {
    public static let defaultMainnetServers: [URL] = [
        URL(string: "wss://bch.imaginary.cash:50004")!,
        URL(string: "wss://fulcrum.greyh.at:50004")!,
        URL(string: "wss://cashnode.bch.ninja:50004")!,
        URL(string: "wss://fulcrum.fountainhead.cash:50002")!,
        URL(string: "wss://electrum.imaginary.cash:50004")!,
        URL(string: "wss://electroncash.dk:50004")!,
        URL(string: "wss://bch.loping.net:50004")!,
        URL(string: "wss://fulcrum.jettscythe.xyz:50004")!
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
        return components.url ?? server
    }
}
