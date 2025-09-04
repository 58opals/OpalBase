// Network+Telemetry+Privacy.swift

import Foundation

extension Network.Telemetry {
    public struct Privacy: Sendable {
        public var batchSize: Int
        public var jitter: TimeInterval
        public var rateCap: Int
        public var rateInterval: TimeInterval
        
        public init(
            batchSize: Int = 10,
            jitter: TimeInterval = 0.5,
            rateCap: Int = 100,
            rateInterval: TimeInterval = 60
        ) {
            self.batchSize = batchSize
            self.jitter = jitter
            self.rateCap = rateCap
            self.rateInterval = rateInterval
        }
        
        public func jitterDelay() -> UInt64 {
            let max = UInt64(jitter * 1_000_000_000)
            return UInt64.random(in: 0...max)
        }
    }
}
