// Telemetry+MetricsSnapshot.swift

import Foundation

extension Telemetry {
    public struct MetricsSnapshot: Sendable, Encodable {
        public struct EventCounters: Sendable, Encodable {
            public let total: Int
            public let failures: Int
            
            public var successRate: Double? {
                guard total > 0 else { return nil }
                return Double(total - failures) / Double(total)
            }
            
            private enum CodingKeys: String, CodingKey {
                case total
                case failures
                case successRate
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(total, forKey: .total)
                try container.encode(failures, forKey: .failures)
                try container.encode(successRate, forKey: .successRate)
            }
        }
        
        public struct ValueAggregate: Sendable, Encodable {
            public let count: Int
            public let sum: Double
            public let minimum: Double?
            public let maximum: Double?
            
            public var average: Double? {
                guard count > 0 else { return nil }
                return sum / Double(count)
            }
            
            private enum CodingKeys: String, CodingKey {
                case count
                case sum
                case minimum
                case maximum
                case average
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(count, forKey: .count)
                try container.encode(sum, forKey: .sum)
                try container.encode(minimum, forKey: .minimum)
                try container.encode(maximum, forKey: .maximum)
                try container.encode(average, forKey: .average)
            }
        }
        
        public let timestamp: Date
        public let eventCounters: [String: EventCounters]
        public let valueAggregates: [String: ValueAggregate]
    }
}
