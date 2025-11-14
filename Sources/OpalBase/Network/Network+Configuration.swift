// Network+Configuration.swift

import Foundation

extension Network {
    public struct Configuration: Sendable, Equatable {
        public var serverURLs: [URL]
        public var connectionTimeout: Duration
        public var maximumMessageSize: Int
        public var reconnect: ReconnectConfiguration
        
        public init(
            serverURLs: [URL],
            connectionTimeout: Duration = .seconds(10),
            maximumMessageSize: Int = 64 * 1_024 * 1_024,
            reconnect: ReconnectConfiguration = .default
        ) {
            self.serverURLs = serverURLs
            self.connectionTimeout = connectionTimeout
            self.maximumMessageSize = maximumMessageSize
            self.reconnect = reconnect
        }
    }
    
    public struct ReconnectConfiguration: Sendable, Equatable {
        public var maximumAttempts: Int
        public var initialDelay: Duration
        public var maximumDelay: Duration
        public var jitterMultiplierRange: ClosedRange<Double>
        
        public static let `default` = Self(
            maximumAttempts: 8,
            initialDelay: .seconds(1.5),
            maximumDelay: .seconds(30),
            jitterMultiplierRange: 0.8 ... 1.3
        )
        
        public init(
            maximumAttempts: Int,
            initialDelay: Duration,
            maximumDelay: Duration,
            jitterMultiplierRange: ClosedRange<Double>
        ) {
            self.maximumAttempts = maximumAttempts
            self.initialDelay = initialDelay
            self.maximumDelay = maximumDelay
            self.jitterMultiplierRange = jitterMultiplierRange
        }
    }
}
