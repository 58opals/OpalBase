import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network.Configuration", .tags(.network))
struct NetworkConfigurationTests {
    private static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let backupServerAddress = URL(string: "wss://bch.loping.net:50002")!
    private static let faultyServerAddress = URL(string: "wss://fulcrum.jettscythe.xyz:50004")!
    private static let invalidServerAddress = URL(string: "not a url")!
    private static let sampleCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a"
    private static let invalidCashAddress = "bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6z"
    
    @Test("initializes with default connection values")
    func testInitializeConfigurationWithDefaults() {
        let configuration = Network.Configuration(serverURLs: [Self.primaryServerAddress])
        
        #expect(configuration.serverURLs == [Self.primaryServerAddress])
        #expect(configuration.connectionTimeout == .seconds(10))
        #expect(configuration.maximumMessageSize == 64 * 1_024 * 1_024)
        #expect(configuration.reconnect == .default)
    }
    
    @Test("Provides wallet-friendly defaults")
    func testDefaultsProvideWalletFriendlySettings() throws {
        let primaryServer = URL(string: "wss://bch.imaginary.cash:50004")!
        let configuration = Network.Configuration(serverURLs: [primaryServer])
        
        #expect(configuration.serverURLs == [primaryServer])
        #expect(configuration.connectionTimeout == .seconds(10))
        #expect(configuration.maximumMessageSize == 64 * 1_024 * 1_024)
        #expect(configuration.reconnect == .default)
        #expect(configuration.reconnect.maximumAttempts == 8)
        #expect(configuration.reconnect.initialDelay == .seconds(1.5))
        #expect(configuration.reconnect.maximumDelay == .seconds(30))
        #expect(configuration.reconnect.jitterMultiplierRange.lowerBound < configuration.reconnect.jitterMultiplierRange.upperBound)
    }
    
    @Test("default reconnect strategy matches recommended jitter and delays")
    func testReconnectDefaultConfigurationValues() {
        let reconnect = Network.ReconnectConfiguration.default
        
        #expect(reconnect.maximumAttempts == 8)
        #expect(reconnect.initialDelay == .seconds(1.5))
        #expect(reconnect.maximumDelay == .seconds(30))
        #expect(reconnect.jitterMultiplierRange.lowerBound == 0.8)
        #expect(reconnect.jitterMultiplierRange.upperBound == 1.3)
    }
    
    @Test("Connects to a live Fulcrum server", .tags(.network), .timeLimit(.minutes(1)))
    func testConnectionToFulcrumServer() async throws {
        let configuration = Network.Configuration(
            serverURLs: [
                URL(string: "wss://bch.imaginary.cash:50004")!,
                URL(string: "wss://bch.loping.net:50002")!
            ],
            connectionTimeout: .seconds(15),
            maximumMessageSize: 32 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 3,
                initialDelay: .seconds(1),
                maximumDelay: .seconds(5),
                jitterMultiplierRange: 0.9 ... 1.1
            )
        )
        
        let client = try await Network.FulcrumClient(configuration: configuration)
        defer { Task { await client.stop() } }
        
        let tip = try await client.request(
            method: .blockchain(.headers(.getTip)),
            responseType: Response.Result.Blockchain.Headers.GetTip.self
        )
        
        #expect(tip.height > 0)
        #expect(!tip.hex.isEmpty)
    }
    
    @Test("connects to fulcrum using wallet centric configuration", .timeLimit(.minutes(1)))
    func testConnectFulcrumWithCustomConfiguration() async throws {
        let configuration = Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
            connectionTimeout: .seconds(8),
            maximumMessageSize: 8 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 2,
                initialDelay: .seconds(0.5),
                maximumDelay: .seconds(4),
                jitterMultiplierRange: 0.9 ... 1.1
            )
        )
        
        let client = try await Network.FulcrumClient(configuration: configuration)
        do {
            let balance: SwiftFulcrum.Response.Result.Blockchain.Address.GetBalance = try await client.request(
                method: .blockchain(
                    .address(
                        .getBalance(address: Self.sampleCashAddress, tokenFilter: nil)
                    )
                )
            )
            #expect(balance.confirmed >= 0)
            
            try await client.reconnect()
            
            let history: SwiftFulcrum.Response.Result.Blockchain.Address.GetHistory = try await client.request(
                method: .blockchain(
                    .address(
                        .getHistory(
                            address: Self.sampleCashAddress,
                            fromHeight: nil,
                            toHeight: nil,
                            includeUnconfirmed: true
                        )
                    )
                )
            )
            #expect(!history.transactions.isEmpty)
            
            await client.stop()
        } catch {
            await client.stop()
            throw error
        }
    }
    
    @Test("connects with empty server list by falling back to bundled bootstrap", .timeLimit(.minutes(1)))
    func testConnectFulcrumUsingBundledBootstrapServers() async throws {
        let configuration = Network.Configuration(serverURLs: [])
        
        let client = try await Network.FulcrumClient(configuration: configuration)
        do {
            let tip: SwiftFulcrum.Response.Result.Blockchain.Headers.GetTip = try await client.request(
                method: .blockchain(
                    .headers(.getTip)
                )
            )
            
            #expect(tip.height > 0)
            #expect(!tip.hex.isEmpty)
            
            await client.stop()
        } catch {
            await client.stop()
            throw error
        }
    }
    
    @Test("Detects configuration changes for reconnect strategies")
    func testEqualityRecognizesMeaningfulChanges() throws {
        let primaryServer = URL(string: "wss://bch.imaginary.cash:50004")!
        let fallbackServer = URL(string: "wss://bch.loping.net:50002")!
        
        let baseConfiguration = Network.Configuration(
            serverURLs: [primaryServer, fallbackServer],
            connectionTimeout: .seconds(20),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 5,
                initialDelay: .seconds(2),
                maximumDelay: .seconds(20),
                jitterMultiplierRange: 1.0 ... 1.0
            )
        )
        
        let identicalConfiguration = Network.Configuration(
            serverURLs: [primaryServer, fallbackServer],
            connectionTimeout: .seconds(20),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 5,
                initialDelay: .seconds(2),
                maximumDelay: .seconds(20),
                jitterMultiplierRange: 1.0 ... 1.0
            )
        )
        
        var adjustedConfiguration = baseConfiguration
        adjustedConfiguration.serverURLs.removeFirst()
        
        #expect(baseConfiguration == identicalConfiguration)
        #expect(baseConfiguration != adjustedConfiguration)
        #expect(adjustedConfiguration.serverURLs == [fallbackServer])
        #expect(adjustedConfiguration.reconnect.jitterMultiplierRange == 1.0 ... 1.0)
    }
}
