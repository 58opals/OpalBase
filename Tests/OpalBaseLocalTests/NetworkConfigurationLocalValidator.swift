// NetworkConfigurationLocalValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Network.Configuration (Local)", .tags(.unit))
struct NetworkConfigurationLocalValidator {
    private static let primaryServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    private static let backupServerAddress = URL(string: "wss://bch.loping.net:50004")!
    
    @Test("initializes with default connection values")
    func initializeConfigurationWithDefaults() {
        let configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress])
        
        #expect(configuration.serverURLs == [Self.primaryServerAddress])
        #expect(configuration.connectTimeout == .seconds(10))
        #expect(configuration.maximumMessageSize == 64 * 1_024 * 1_024)
        #expect(configuration.reconnectConfiguration == .defaultValue)
        #expect(configuration.network == .mainnet)
    }
    
    @Test("Provides wallet-friendly defaults")
    func defaultsProvideWalletFriendlySettings() throws {
        let primaryServer = URL(string: "wss://bch.imaginary.cash:50004")!
        let configuration = OpalBase.Network.Configuration(serverURLs: [primaryServer])
        
        #expect(configuration.serverURLs == [primaryServer])
        #expect(configuration.connectTimeout == .seconds(10))
        #expect(configuration.maximumMessageSize == 64 * 1_024 * 1_024)
        #expect(configuration.reconnectConfiguration == .defaultValue)
        #expect(configuration.reconnectConfiguration.maximumAttempts == 8)
        #expect(configuration.reconnectConfiguration.initialDelay == .seconds(1.5))
        #expect(configuration.reconnectConfiguration.maximumDelay == .seconds(30))
        #expect(configuration.reconnectConfiguration.jitterMultiplierRange.lowerBound < configuration.reconnectConfiguration.jitterMultiplierRange.upperBound)
        #expect(configuration.network == .mainnet)
    }
    
    @Test("default reconnect strategy matches recommended jitter and delays")
    func reconnectDefaultConfigurationValues() {
        let reconnect = OpalBase.Network.ReconnectConfiguration.defaultValue
        
        #expect(reconnect.maximumAttempts == 8)
        #expect(reconnect.initialDelay == .seconds(1.5))
        #expect(reconnect.maximumDelay == .seconds(30))
        #expect(reconnect.jitterMultiplierRange.lowerBound == 0.8)
        #expect(reconnect.jitterMultiplierRange.upperBound == 1.3)
    }
    
    @Test("Detects configuration changes for reconnect strategies")
    func equalityRecognizesMeaningfulChanges() throws {
        let primaryServer = URL(string: "wss://bch.imaginary.cash:50004")!
        let fallbackServer = URL(string: "wss://bch.loping.net:50004")!
        
        let baseConfiguration = OpalBase.Network.Configuration(
            serverURLs: [primaryServer, fallbackServer],
            connectTimeout: .seconds(20),
            maximumMessageSize: 16 * 1_024 * 1_024,
            reconnect: .init(
                maximumAttempts: 5,
                initialDelay: .seconds(2),
                maximumDelay: .seconds(20),
                jitterMultiplierRange: 1.0 ... 1.0
            )
        )
        
        let identicalConfiguration = OpalBase.Network.Configuration(
            serverURLs: [primaryServer, fallbackServer],
            connectTimeout: .seconds(20),
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
        #expect(adjustedConfiguration.reconnectConfiguration.jitterMultiplierRange == 1.0 ... 1.0)
    }

    @Test("deprecated connectionTimeout alias round-trips to connectTimeout")
    @available(*, deprecated, message: "Compatibility validator for deprecated API")
    func deprecatedConnectionTimeoutAliasRoundTrips() {
        var configuration = OpalBase.Network.Configuration(
            serverURLs: [Self.primaryServerAddress],
            connectTimeout: .seconds(6)
        )

        #expect(configuration.connectionTimeout == .seconds(6))

        configuration.connectionTimeout = .seconds(9)

        #expect(configuration.connectTimeout == .seconds(9))
    }

    @Test("deprecated initializer forwards connectionTimeout into connectTimeout")
    @available(*, deprecated, message: "Compatibility validator for deprecated API")
    func deprecatedInitializerForwardsConnectionTimeout() {
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [Self.primaryServerAddress],
            connectionTimeout: .seconds(7)
        )

        #expect(configuration.connectTimeout == .seconds(7))
    }
}
