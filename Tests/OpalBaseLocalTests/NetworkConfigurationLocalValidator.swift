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

    @Test(
        "configuration clamps non-positive connect timeouts",
        arguments: [Duration.zero, .seconds(-1)]
    )
    func configurationClampsNonPositiveConnectTimeouts(_ connectTimeout: Duration) {
        var configuration = OpalBase.Network.Configuration(
            serverURLs: [Self.primaryServerAddress],
            connectTimeout: connectTimeout
        )

        #expect(configuration.connectTimeout == .milliseconds(1))

        configuration.connectTimeout = connectTimeout

        #expect(configuration.connectTimeout == .milliseconds(1))
    }

    @Test(
        "fulcrum request timeouts clamp non-positive durations",
        arguments: [Duration.zero, .seconds(-1)],
        FulcrumRequestTimeoutField.allCases
    )
    fileprivate func fulcrumRequestTimeoutsClampNonPositiveDurations(
        _ timeout: Duration,
        _ field: FulcrumRequestTimeoutField
    ) {
        var timeouts = Self.makeFulcrumRequestTimeouts(timeout)

        #expect(timeouts[keyPath: field.keyPath] == .milliseconds(1))

        timeouts[keyPath: field.keyPath] = timeout

        #expect(timeouts[keyPath: field.keyPath] == .milliseconds(1))
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

    @Test("reconnect configuration clamps negative maximum attempts")
    func reconnectConfigurationClampsNegativeMaximumAttempts() {
        var reconnect = OpalBase.Network.ReconnectConfiguration(
            maximumAttempts: -1,
            initialDelay: .seconds(1),
            maximumDelay: .seconds(2),
            jitterMultiplierRange: 1.0 ... 1.0
        )

        #expect(reconnect.maximumAttempts == 0)

        reconnect.maximumAttempts = -2

        #expect(reconnect.maximumAttempts == 0)
    }

    @Test("reconnect configuration clamps non-positive and inverted delays")
    func reconnectConfigurationClampsNonPositiveAndInvertedDelays() {
        var reconnect = OpalBase.Network.ReconnectConfiguration(
            maximumAttempts: 1,
            initialDelay: .zero,
            maximumDelay: .seconds(-1),
            jitterMultiplierRange: 1.0 ... 1.0
        )

        #expect(reconnect.initialDelay == .milliseconds(1))
        #expect(reconnect.maximumDelay == .milliseconds(1))

        reconnect.initialDelay = .seconds(5)

        #expect(reconnect.initialDelay == .seconds(5))
        #expect(reconnect.maximumDelay == .seconds(5))

        reconnect.maximumDelay = .seconds(1)

        #expect(reconnect.maximumDelay == .seconds(5))
    }

    @Test("reconnect configuration clamps invalid jitter multipliers")
    func reconnectConfigurationClampsInvalidJitterMultipliers() {
        var reconnect = OpalBase.Network.ReconnectConfiguration(
            maximumAttempts: 1,
            initialDelay: .seconds(1),
            maximumDelay: .seconds(2),
            jitterMultiplierRange: -1.0 ... Double.infinity
        )

        #expect(reconnect.jitterMultiplierRange == 1.0 ... 1.0)

        reconnect.jitterMultiplierRange = 0.75 ... Double.infinity

        #expect(reconnect.jitterMultiplierRange == 0.75 ... 1.0)
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

private extension NetworkConfigurationLocalValidator {
    static func makeFulcrumRequestTimeouts(_ timeout: Duration) -> OpalBase.Network.FulcrumRequestTimeout {
        OpalBase.Network.FulcrumRequestTimeout(
            serverPing: timeout,
            serverVersion: timeout,
            serverFeatures: timeout,
            relayFee: timeout,
            feeEstimation: timeout,
            headersTip: timeout,
            headersSubscription: timeout,
            addressBalance: timeout,
            addressUnspent: timeout,
            addressHistory: timeout,
            addressSubscription: timeout,
            addressFirstUse: timeout,
            addressMempool: timeout,
            addressScriptHash: timeout,
            scriptHashHistory: timeout,
            scriptHashUnspent: timeout,
            transactionBroadcast: timeout,
            transactionConfirmations: timeout,
            transactionMerkleProof: timeout,
            transactionPositionResolution: timeout,
            mempoolInfo: timeout,
            mempoolFeeHistogram: timeout
        )
    }

    enum FulcrumRequestTimeoutField: CaseIterable, Sendable {
        case serverPing
        case serverVersion
        case serverFeatures
        case relayFee
        case feeEstimation
        case headersTip
        case headersSubscription
        case addressBalance
        case addressUnspent
        case addressHistory
        case addressSubscription
        case addressFirstUse
        case addressMempool
        case addressScriptHash
        case scriptHashHistory
        case scriptHashUnspent
        case transactionBroadcast
        case transactionConfirmations
        case transactionMerkleProof
        case transactionPositionResolution
        case mempoolInfo
        case mempoolFeeHistogram

        var keyPath: WritableKeyPath<OpalBase.Network.FulcrumRequestTimeout, Duration> {
            switch self {
            case .serverPing: \.serverPing
            case .serverVersion: \.serverVersion
            case .serverFeatures: \.serverFeatures
            case .relayFee: \.relayFee
            case .feeEstimation: \.feeEstimation
            case .headersTip: \.headersTip
            case .headersSubscription: \.headersSubscription
            case .addressBalance: \.addressBalance
            case .addressUnspent: \.addressUnspent
            case .addressHistory: \.addressHistory
            case .addressSubscription: \.addressSubscription
            case .addressFirstUse: \.addressFirstUse
            case .addressMempool: \.addressMempool
            case .addressScriptHash: \.addressScriptHash
            case .scriptHashHistory: \.scriptHashHistory
            case .scriptHashUnspent: \.scriptHashUnspent
            case .transactionBroadcast: \.transactionBroadcast
            case .transactionConfirmations: \.transactionConfirmations
            case .transactionMerkleProof: \.transactionMerkleProof
            case .transactionPositionResolution: \.transactionPositionResolution
            case .mempoolInfo: \.mempoolInfo
            case .mempoolFeeHistogram: \.mempoolFeeHistogram
            }
        }
    }
}
