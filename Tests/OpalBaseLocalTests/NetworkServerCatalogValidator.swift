// NetworkServerCatalogValidator.swift

import Foundation
import SwiftFulcrum
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.ServerCatalog", .tags(.unit, .network))
struct NetworkServerCatalogValidator {
    @Test("opal defaults provide healthy per-environment catalogs")
    func opalDefaultsProvidePerEnvironmentCatalogs() {
        let catalog = OpalBase.Network.ServerCatalog.opalDefault
        
        let mainnetServers = catalog.listServers(for: .mainnet)
        let chipnetServers = catalog.listServers(for: .chipnet)
        let testnetServers = catalog.listServers(for: .testnet)
        
        #expect(mainnetServers.contains(URL(string: "wss://bch.imaginary.cash:50004")!))
        #expect(mainnetServers.contains(URL(string: "wss://bch.loping.net:50004")!))
        #expect(!mainnetServers.contains(where: { $0.host == "fulcrum.fountainhead.cash" }))
        #expect(!mainnetServers.contains(where: { $0.host == "fulcrum.jettscythe.xyz" }))
        #expect(chipnetServers == [URL(string: "wss://chipnet.imaginary.cash:50004")!])
        #expect(testnetServers.contains(URL(string: "wss://testnet.imaginary.cash:50004")!))
        #expect(!testnetServers.contains(where: { $0.host == "chipnet.imaginary.cash" }))
    }

    @Test("catalog URL mutation preserves normalization")
    func catalogURLMutationPreservesNormalization() {
        var catalog = OpalBase.Network.ServerCatalog(
            mainnetServers: .init(),
            chipnetServers: .init(),
            testnetServers: .init()
        )

        catalog.mainnetServers = [
            URL(string: "https://main.example.com:443/")!,
            URL(string: "wss://main.example.com")!,
            URL(string: "ftp://main.example.com")!
        ]
        catalog.chipnetServers = [
            URL(string: "http://chip.example.com:80/")!,
            URL(string: "ws://chip.example.com")!
        ]
        catalog.testnetServers = [
            URL(string: "wss://test.example.com:0")!,
            URL(string: "wss://test.example.com:50004")!
        ]

        #expect(catalog.mainnetServers == [URL(string: "wss://main.example.com")!])
        #expect(catalog.chipnetServers == [URL(string: "ws://chip.example.com")!])
        #expect(catalog.testnetServers == [URL(string: "wss://test.example.com:50004")!])
    }
    
    @Test("network environments map one-to-one to FulcrumClient networks")
    func environmentsMapOneToOneToFulcrumNetworks() {
        #expect(OpalBase.Network.Environment.mainnet.fulcrumNetwork == SwiftFulcrum.Client.Configuration.Network.mainnet)
        #expect(OpalBase.Network.Environment.testnet.fulcrumNetwork == SwiftFulcrum.Client.Configuration.Network.testnet)
        #expect(OpalBase.Network.Environment.chipnet.fulcrumNetwork == SwiftFulcrum.Client.Configuration.Network.chipnet)
        #expect(OpalBase.Network.Environment(SwiftFulcrum.Client.Configuration.Network.mainnet) == .mainnet)
        #expect(OpalBase.Network.Environment(SwiftFulcrum.Client.Configuration.Network.testnet) == .testnet)
        #expect(OpalBase.Network.Environment(SwiftFulcrum.Client.Configuration.Network.chipnet) == .chipnet)
    }
    
    @Test("server catalog loader keeps overrides authoritative and appends fallback")
    func configurationLoaderKeepsOverridesAuthoritative() async throws {
        let overrideServer = URL(string: "wss://override.opalwallet.example:50004")!
        let defaultServer = URL(string: "wss://bch.imaginary.cash:50004")!
        let fallbackServer = URL(string: "wss://fallback.opalwallet.example:50004")!
        let catalog = OpalBase.Network.ServerCatalog(
            mainnetServers: [defaultServer],
            chipnetServers: .init(),
            testnetServers: .init()
        )
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [overrideServer],
            serverCatalog: catalog,
            connectTimeout: .seconds(1),
            maximumMessageSize: 1_024,
            reconnect: .init(
                maximumAttempts: 1,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(1),
                jitterMultiplierRange: 1.0 ... 1.0
            ),
            network: .mainnet
        )
        
        let loader = configuration.makeFulcrumServerCatalogRepository()
        let servers = try await loader.loadServers(
            for: configuration.network.fulcrumNetwork,
            fallback: [fallbackServer]
        )
        #expect(servers == [overrideServer, fallbackServer])
        #expect(!servers.contains(defaultServer))
    }
    
    @Test("loader rejects mismatched Fulcrum network")
    func configurationLoaderRejectsMismatchedFulcrumNetwork() async throws {
        let configuration = OpalBase.Network.Configuration(
            serverURLs: .init(),
            network: .mainnet
        )
        
        let loader = configuration.makeFulcrumServerCatalogRepository()
        
        let error = try await Self.captureFulcrumClientError {
            _ = try await loader.loadServers(for: .testnet, fallback: .init())
        }
        guard case .client(.protocolMismatch(let optionalMessage)) = error else {
            throw FulcrumClientErrorCaptureFailure.unexpected(error)
        }

        let message = try #require(optionalMessage)
        #expect(message.contains("configuredEnvironment=mainnet"))
        #expect(message.contains("expectedFulcrumNetwork=mainnet"))
        #expect(message.contains("requestedFulcrumNetwork=testnet"))
    }
    
    @Test("loader augments chipnet defaults with provided fallback")
    func configurationMergesFallbackWithChipnetDefaults() async throws {
        let fallbackServer = URL(string: "wss://fallback.chipnet.example:50004")!
        let configuration = OpalBase.Network.Configuration(
            serverURLs: .init(),
            network: .chipnet
        )
        
        let loader = configuration.makeFulcrumServerCatalogRepository()
        let servers = try await loader.loadServers(for: configuration.network.fulcrumNetwork, fallback: [fallbackServer])
        
        #expect(servers.contains(fallbackServer))
        #expect(servers.contains(where: { $0.host == "chipnet.imaginary.cash" }))
        #expect(!servers.contains(where: { $0.host == "testnet.imaginary.cash" }))
    }
    
    @Test("loader augments testnet defaults with provided fallback")
    func configurationMergesFallbackWithTestnetDefaults() async throws {
        let fallbackServer = URL(string: "wss://fallback.testnet.example:50004")!
        let configuration = OpalBase.Network.Configuration(
            serverURLs: .init(),
            network: .testnet
        )
        
        let loader = configuration.makeFulcrumServerCatalogRepository()
        let servers = try await loader.loadServers(for: configuration.network.fulcrumNetwork, fallback: [fallbackServer])
        
        #expect(servers.contains(fallbackServer))
        #expect(servers.contains(where: { $0.host == "testnet.imaginary.cash" }))
        #expect(!servers.contains(where: { $0.host == "chipnet.imaginary.cash" }))
    }
    
    @Test("bootstrap server selection respects configured environment")
    func bootstrapServersRespectConfiguredEnvironment() {
        let chipnetConfiguration = OpalBase.Network.Configuration(serverURLs: .init(), network: .chipnet)
        let testnetConfiguration = OpalBase.Network.Configuration(serverURLs: .init(), network: .testnet)
        
        let chipnetBootstrap = chipnetConfiguration.fulcrumBootstrapServers
        let testnetBootstrap = testnetConfiguration.fulcrumBootstrapServers
        
        #expect(chipnetBootstrap.contains(where: { $0.host == "chipnet.imaginary.cash" }))
        #expect(!chipnetBootstrap.contains(where: { $0.host == "testnet.imaginary.cash" }))
        #expect(testnetBootstrap.contains(where: { $0.host == "testnet.imaginary.cash" }))
        #expect(!testnetBootstrap.contains(where: { $0.host == "chipnet.imaginary.cash" }))
    }

    @Test("bootstrap server selection keeps overrides authoritative")
    func bootstrapServersKeepOverridesAuthoritative() {
        let overrideServer = URL(string: "wss://override.opalwallet.example:50004")!
        let defaultServer = URL(string: "wss://bch.imaginary.cash:50004")!
        let catalog = OpalBase.Network.ServerCatalog(
            mainnetServers: [defaultServer],
            chipnetServers: .init(),
            testnetServers: .init()
        )
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [overrideServer],
            serverCatalog: catalog,
            network: .mainnet
        )

        #expect(configuration.fulcrumBootstrapServers == [overrideServer])
        #expect(!configuration.fulcrumBootstrapServers.contains(defaultServer))
    }
    
    @Test("normalizes schemes, removes invalid entries, and deduplicates")
    func normalizationFiltersAndDeduplicatesServers() throws {
        let rawServers = [
            URL(string: "wss://bch.imaginary.cash:50004")!,
            URL(string: "HTTPS://bch.imaginary.cash:50004")!,
            URL(string: "http://chipnet.imaginary.cash:50004")!,
            URL(string: "ftp://should-be-ignored.example.com")!
        ]
        
        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)
        #expect(normalized.count == 2)
        let firstServer = try #require(normalized.first)
        #expect(firstServer.scheme == "wss")
        #expect(normalized.contains(where: { $0.scheme == "ws" && $0.host == "chipnet.imaginary.cash" }))
        #expect(!normalized.contains(where: { $0.scheme == "ftp" }))
    }

    @Test("normalizes default websocket ports before deduplication")
    func normalizationCollapsesDefaultWebSocketPorts() {
        let rawServers = [
            URL(string: "https://default-port.example.com:443")!,
            URL(string: "wss://default-port.example.com")!,
            URL(string: "http://insecure-default.example.com:80")!,
            URL(string: "ws://insecure-default.example.com")!
        ]

        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)

        #expect(normalized == [
            URL(string: "wss://default-port.example.com")!,
            URL(string: "ws://insecure-default.example.com")!
        ])
    }

    @Test("normalizes root websocket paths before deduplication")
    func normalizationCollapsesRootWebSocketPaths() {
        let rawServers = [
            URL(string: "wss://root-path.example.com")!,
            URL(string: "wss://root-path.example.com/")!,
            URL(string: "https://root-path.example.com:443/")!
        ]

        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)

        #expect(normalized == [URL(string: "wss://root-path.example.com")!])
    }

    @Test("normalizes websocket fragments before deduplication")
    func normalizationCollapsesWebSocketFragments() {
        let rawServers = [
            URL(string: "wss://fragment.example.com")!,
            URL(string: "wss://fragment.example.com#ignored")!,
            URL(string: "https://fragment.example.com:443/#also-ignored")!
        ]

        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)

        #expect(normalized == [URL(string: "wss://fragment.example.com")!])
    }

    @Test("normalizes websocket queries before deduplication")
    func normalizationCollapsesWebSocketQueries() {
        let rawServers = [
            URL(string: "wss://query.example.com?token=secret")!,
            URL(string: "wss://query.example.com")!,
            URL(string: "https://query.example.com:443/?token=also-secret")!
        ]

        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)

        #expect(normalized == [URL(string: "wss://query.example.com")!])
    }

    @Test("normalizes websocket hosts before deduplication")
    func normalizationLowercasesWebSocketHosts() {
        let rawServers = [
            URL(string: "HTTPS://UPPERCASE.EXAMPLE.COM:443")!,
            URL(string: "wss://uppercase.example.com")!
        ]

        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)

        #expect(normalized == [URL(string: "wss://uppercase.example.com")!])
    }

    @Test("normalization preserves case-sensitive websocket paths when deduplicating")
    func normalizationPreservesCaseSensitiveWebSocketPaths() {
        let rawServers = [
            URL(string: "wss://PATH.example.com/API")!,
            URL(string: "wss://path.example.com/API")!,
            URL(string: "wss://path.example.com/api")!
        ]

        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)

        #expect(normalized == [
            URL(string: "wss://path.example.com/API")!,
            URL(string: "wss://path.example.com/api")!
        ])
    }

    @Test("normalization rejects websocket URLs without hosts")
    func normalizationRejectsWebSocketURLsWithoutHosts() {
        let rawServers = [
            URL(string: "wss:///missing-host")!,
            URL(string: "ws://")!,
            URL(string: "https:/missing-host")!,
            URL(string: "wss://./relative-host")!,
            URL(string: "wss://../relative-parent-host")!,
            URL(string: "wss://valid.example.com:50004")!
        ]

        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)

        #expect(normalized == [URL(string: "wss://valid.example.com:50004")!])
    }
    
    @Test("normalization rejects invalid websocket ports")
    func normalizationRejectsInvalidWebSocketPorts() {
        let rawServers = [
            URL(string: "wss://invalid-port.example.com:0")!,
            URL(string: "wss://valid.example.com:50004")!
        ]
        
        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)
        
        #expect(normalized == [URL(string: "wss://valid.example.com:50004")!])
    }

    @Test("normalization rejects websocket URLs with embedded credentials")
    func normalizationRejectsWebSocketURLsWithEmbeddedCredentials() {
        let rawServers = [
            URL(string: "wss://user:secret@credential.example.com:50004")!,
            URL(string: "https://user@credential.example.com")!,
            URL(string: "wss://valid.example.com:50004")!
        ]

        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)

        #expect(normalized == [URL(string: "wss://valid.example.com:50004")!])
    }

    @Test("normalization rejects websocket URLs with malformed host labels")
    func normalizationRejectsWebSocketURLsWithMalformedHostLabels() {
        let oversizedLabel = String(repeating: "a", count: 64)
        let oversizedHost = String(repeating: "a.", count: 127) + "example.com"
        let rawServers = [
            URL(string: "wss://.leading-label.example.com")!,
            URL(string: "wss://empty-label..example.com")!,
            URL(string: "wss://-leading-hyphen.example.com")!,
            URL(string: "wss://trailing-hyphen-.example.com")!,
            URL(string: "wss://\(oversizedLabel).example.com")!,
            URL(string: "wss://\(oversizedHost)")!,
            URL(string: "wss://bad_host.example.com")!,
            URL(string: "wss://%2e%2e.example.com")!,
            URL(string: "wss://valid.example.com:50004")!
        ]

        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)

        #expect(normalized == [URL(string: "wss://valid.example.com:50004")!])
    }

    @Test("normalization preserves internet protocol literal websocket hosts")
    func normalizationPreservesInternetProtocolLiteralWebSocketHosts() {
        let rawServers = [
            URL(string: "wss://[::1]:50004")!
        ]

        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)

        #expect(normalized == [URL(string: "wss://[::1]:50004")!])
    }

    @Test("normalization rejects websocket URLs with path traversal")
    func normalizationRejectsWebSocketPathTraversal() throws {
        let rawServers = [
            try #require(URL(string: "wss://path.example.com/../admin")),
            try #require(URL(string: "wss://path.example.com/%2e%2e/admin")),
            try #require(URL(string: "wss://path.example.com/%252e%252e/admin")),
            try #require(URL(string: "wss://path.example.com/a/%2e/b")),
            try #require(URL(string: "wss://valid.example.com:50004"))
        ]

        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)

        #expect(normalized == [URL(string: "wss://valid.example.com:50004")!])
    }
    
    @Test("merged server catalogs preserve priority ordering and uniqueness")
    func mergedServersPreservePriorityOrdering() throws {
        let primary = [
            URL(string: "wss://primary.example.com")!,
            URL(string: "https://duplicate.example.com")!
        ]
        let fallback = [
            URL(string: "wss://duplicate.example.com")!,
            URL(string: "wss://fallback.example.com")!
        ]
        
        let merged = OpalBase.Network.ServerCatalog.makeMergedServers(primary: primary, fallback: fallback)
        
        try #require(merged.count == 3)
        #expect(merged[0].host == "primary.example.com")
        #expect(merged[1].host == "duplicate.example.com")
        #expect(merged[1].scheme == "wss")
        #expect(merged[2].host == "fallback.example.com")
    }

    enum FulcrumClientErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    private static func captureFulcrumClientError(
        _ work: () async throws -> Void
    ) async throws -> SwiftFulcrum.Client.Error {
        do {
            try await work()
            throw FulcrumClientErrorCaptureFailure.didNotThrow
        } catch let error as SwiftFulcrum.Client.Error {
            return error
        } catch let error as FulcrumClientErrorCaptureFailure {
            throw error
        } catch {
            throw FulcrumClientErrorCaptureFailure.unexpected(error)
        }
    }
}
