// OpalBase+Network+ReconnectConfiguration.swift

import Foundation

extension _OpalBase.Network {
    public struct ReconnectConfiguration: Sendable, Equatable {
        public var maximumAttempts: Int {
            didSet {
                maximumAttempts = Self.clampedMaximumAttempts(maximumAttempts)
            }
        }
        public var initialDelay: Duration {
            didSet {
                initialDelay = Self.clampedReconnectDelay(initialDelay)
                maximumDelay = Self.clampedMaximumDelay(maximumDelay, minimum: initialDelay)
            }
        }
        public var maximumDelay: Duration {
            didSet {
                maximumDelay = Self.clampedMaximumDelay(maximumDelay, minimum: initialDelay)
            }
        }
        public var jitterMultiplierRange: ClosedRange<Double> {
            didSet {
                jitterMultiplierRange = Self.clampedJitterMultiplierRange(jitterMultiplierRange)
            }
        }
        
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
            self.maximumAttempts = Self.clampedMaximumAttempts(maximumAttempts)
            self.initialDelay = Self.clampedReconnectDelay(initialDelay)
            self.maximumDelay = Self.clampedMaximumDelay(maximumDelay, minimum: self.initialDelay)
            self.jitterMultiplierRange = Self.clampedJitterMultiplierRange(jitterMultiplierRange)
        }

        private static func clampedMaximumAttempts(_ maximumAttempts: Int) -> Int {
            max(0, maximumAttempts)
        }

        private static func clampedReconnectDelay(_ delay: Duration) -> Duration {
            max(.milliseconds(1), delay)
        }

        private static func clampedMaximumDelay(_ maximumDelay: Duration, minimum initialDelay: Duration) -> Duration {
            max(clampedReconnectDelay(initialDelay), maximumDelay)
        }

        private static func clampedJitterMultiplierRange(_ jitterMultiplierRange: ClosedRange<Double>) -> ClosedRange<Double> {
            let lowerBound = clampedJitterMultiplier(jitterMultiplierRange.lowerBound, fallback: 1.0)
            let upperBound = clampedJitterMultiplier(jitterMultiplierRange.upperBound, fallback: max(1.0, lowerBound))
            return lowerBound ... max(lowerBound, upperBound)
        }

        private static func clampedJitterMultiplier(_ jitterMultiplier: Double, fallback: Double) -> Double {
            guard jitterMultiplier.isFinite, jitterMultiplier > 0 else {
                return fallback
            }
            return jitterMultiplier
        }
    }
}
