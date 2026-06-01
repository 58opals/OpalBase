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

    @Test(
        "configuration clamps non-positive maximum message sizes",
        arguments: [0, -1]
    )
    func configurationClampsNonPositiveMaximumMessageSizes(_ maximumMessageSize: Int) {
        var configuration = OpalBase.Network.Configuration(
            serverURLs: [Self.primaryServerAddress],
            maximumMessageSize: maximumMessageSize
        )

        #expect(configuration.maximumMessageSize == 1)

        configuration.maximumMessageSize = maximumMessageSize

        #expect(configuration.maximumMessageSize == 1)
    }

    @Test("server URL mutation preserves normalization")
    func serverURLMutationPreservesNormalization() {
        var configuration = OpalBase.Network.Configuration(serverURLs: [Self.primaryServerAddress])
        let normalizedServer = URL(string: "wss://example.com")!

        configuration.serverURLs = [
            URL(string: "https://example.com:443/")!,
            normalizedServer,
            URL(string: "ftp://example.com")!
        ]

        #expect(configuration.serverURLs == [normalizedServer])
    }
    
    @Test("default reconnect strategy matches recommended jitter and delays")
    func validateReconnectDefaultConfigurationValues() {
        let reconnect = OpalBase.Network.ReconnectConfiguration.defaultValue
        
        #expect(reconnect.maximumAttempts == 8)
        #expect(reconnect.initialDelay == .seconds(1.5))
        #expect(reconnect.maximumDelay == .seconds(30))
        #expect(reconnect.jitterMultiplierRange.lowerBound == 0.8)
        #expect(reconnect.jitterMultiplierRange.upperBound == 1.3)
    }
    
    @Test("Detects configuration changes for reconnect strategies")
    func detectMeaningfulConfigurationChanges() {
        let baseConfiguration = OpalBase.Network.Configuration(
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
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
            serverURLs: [Self.primaryServerAddress, Self.backupServerAddress],
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
        #expect(adjustedConfiguration.serverURLs == [Self.backupServerAddress])
        #expect(adjustedConfiguration.reconnectConfiguration.jitterMultiplierRange == 1.0 ... 1.0)
    }

}
