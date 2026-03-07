// OpalBase+Network+ReconnectConfiguration.swift

import Foundation

extension _OpalBase.Network {
    public struct ReconnectConfiguration: Sendable, Equatable {
        public var maximumAttempts: Int
        public var initialDelay: Duration
        public var maximumDelay: Duration
        public var jitterMultiplierRange: ClosedRange<Double>
        
        public static let defaultValue = Self(
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
