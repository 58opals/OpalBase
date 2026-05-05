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
        
        do {
            _ = try await loader.loadServers(for: .testnet, fallback: .init())
            Issue.record("Expected protocol mismatch when requested Fulcrum network does not match configuration.")
        } catch let error as SwiftFulcrum.Client.Error {
            switch error {
            case .client(.protocolMismatch(let message)):
                #expect(message?.contains("configuredEnvironment=mainnet") == true)
                #expect(message?.contains("expectedFulcrumNetwork=mainnet") == true)
                #expect(message?.contains("requestedFulcrumNetwork=testnet") == true)
            default:
                Issue.record("Expected FulcrumClient.Error.client(.protocolMismatch), got \(error).")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
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
    func normalizationFiltersAndDeduplicatesServers() {
        let rawServers = [
            URL(string: "wss://bch.imaginary.cash:50004")!,
            URL(string: "HTTPS://bch.imaginary.cash:50004")!,
            URL(string: "http://chipnet.imaginary.cash:50004")!,
            URL(string: "ftp://should-be-ignored.example.com")!
        ]
        
        let normalized = OpalBase.Network.ServerCatalog.makeNormalizedServers(rawServers)
        #expect(normalized.count == 2)
        #expect(normalized.first?.scheme == "wss")
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
    
    @Test("merged server catalogs preserve priority ordering and uniqueness")
    func mergedServersPreservePriorityOrdering() {
        let primary = [
            URL(string: "wss://primary.example.com")!,
            URL(string: "https://duplicate.example.com")!
        ]
        let secondary = [
            URL(string: "wss://duplicate.example.com")!,
            URL(string: "http://secondary.example.com")!
        ]
        let fallback = [
            URL(string: "wss://fallback.example.com")!
        ]
        
        let merged = OpalBase.Network.ServerCatalog.makeMergedServers(primary: primary, secondary: secondary, fallback: fallback)
        
        #expect(merged.count == 4)
        #expect(merged[0].host == "primary.example.com")
        #expect(merged[1].host == "duplicate.example.com")
        #expect(merged[1].scheme == "wss")
        #expect(merged[2].host == "secondary.example.com")
        #expect(merged[3].host == "fallback.example.com")
    }
}
