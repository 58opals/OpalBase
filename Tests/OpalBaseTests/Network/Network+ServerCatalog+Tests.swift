import Foundation
import SwiftFulcrum
import Testing
@testable import OpalBase

@Suite("Network.ServerCatalog")
struct NetworkServerCatalogTests {
    @Test("opal defaults provide per-environment catalogs")
    func testOpalDefaultsProvidePerEnvironmentCatalogs() {
        let catalog = Network.ServerCatalog.opalDefault
        
        let mainnetServers = catalog.listServers(for: .mainnet)
        let chipnetServers = catalog.listServers(for: .chipnet)
        let testnetServers = catalog.listServers(for: .testnet)
        
        #expect(mainnetServers.contains(URL(string: "wss://bch.imaginary.cash:50004")!))
        #expect(chipnetServers == [URL(string: "wss://chipnet.imaginary.cash:50004")!])
        #expect(testnetServers.contains(URL(string: "wss://testnet.imaginary.cash:50004")!))
        #expect(!testnetServers.contains(where: { $0.host == "chipnet.imaginary.cash" }))
    }
    
    @Test("chipnet maps to Fulcrum testnet framing")
    func testChipnetMapsToFulcrumTestnet() {
        #expect(Network.Environment.chipnet.fulcrumNetwork == Fulcrum.Configuration.Network.testnet)
    }
    
    @Test("server catalog loader merges overrides before defaults")
    func testConfigurationLoaderMergesOverridesBeforeDefaults() async throws {
        let overrideServer = URL(string: "wss://override.opalwallet.example:50004")!
        let defaultServer = URL(string: "wss://bch.imaginary.cash:50004")!
        let catalog = Network.ServerCatalog(
            mainnetServers: [defaultServer],
            chipnetServers: .init(),
            testnetServers: .init()
        )
        let configuration = Network.Configuration(
            serverURLs: [overrideServer],
            serverCatalog: catalog,
            connectionTimeout: .seconds(1),
            maximumMessageSize: 1_024,
            reconnect: .init(
                maximumAttempts: 1,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(1),
                jitterMultiplierRange: 1.0 ... 1.0
            ),
            network: .mainnet
        )
        
        let loader = configuration.makeFulcrumServerCatalogLoader()
        let servers = try await loader.loadServers(for: configuration.network.fulcrumNetwork, fallback: .init())
        #expect(servers.first == overrideServer)
        #expect(servers.contains(defaultServer))
    }
    
    @Test("loader augments chipnet defaults with provided fallback")
    func testConfigurationMergesFallbackWithChipnetDefaults() async throws {
        let fallbackServer = URL(string: "wss://fallback.chipnet.example:50004")!
        let configuration = Network.Configuration(
            serverURLs: .init(),
            network: .chipnet
        )
        
        let loader = configuration.makeFulcrumServerCatalogLoader()
        let servers = try await loader.loadServers(for: configuration.network.fulcrumNetwork, fallback: [fallbackServer])
        
        #expect(servers.contains(fallbackServer))
        #expect(servers.contains(where: { $0.host == "chipnet.imaginary.cash" }))
        #expect(!servers.contains(where: { $0.host == "testnet.imaginary.cash" }))
    }
    
    @Test("normalizes schemes, removes invalid entries, and deduplicates")
    func testNormalizationFiltersAndDeduplicatesServers() {
        let rawServers = [
            URL(string: "wss://bch.imaginary.cash:50004")!,
            URL(string: "HTTPS://bch.imaginary.cash:50004")!,
            URL(string: "http://chipnet.imaginary.cash:50004")!,
            URL(string: "ftp://should-be-ignored.example.com")!
        ]
        
        let normalized = Network.ServerCatalog.makeNormalizedServers(rawServers)
        #expect(normalized.count == 2)
        #expect(normalized.first?.scheme == "wss")
        #expect(normalized.contains(where: { $0.scheme == "ws" && $0.host == "chipnet.imaginary.cash" }))
        #expect(!normalized.contains(where: { $0.scheme == "ftp" }))
    }
    
    @Test("merged server catalogs preserve priority ordering and uniqueness")
    func testMergedServersPreservePriorityOrdering() {
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
        
        let merged = Network.ServerCatalog.makeMergedServers(primary: primary, secondary: secondary, fallback: fallback)
        
        #expect(merged.count == 4)
        #expect(merged[0].host == "primary.example.com")
        #expect(merged[1].host == "duplicate.example.com")
        #expect(merged[1].scheme == "wss")
        #expect(merged[2].host == "secondary.example.com")
        #expect(merged[3].host == "fallback.example.com")
    }
}
