// Telemetry+Event.swift

import Foundation

extension Telemetry {
    public struct Event: Sendable, Encodable {
        public enum Category: String, Sendable, Encodable {
            case diagnostics
            case blockchain
            case wallet
            case network
            case storage
            case security
            case analytics
        }
        
        public var name: String
        public var category: Category
        public var message: String?
        public var metadata: Metadata
        public var metrics: [String: Double]
        public var sensitiveKeys: Set<Metadata.Key>
        public var timestamp: Date
        
        public init(
            name: String,
            category: Category,
            message: String? = nil,
            metadata: Metadata = .init(),
            metrics: [String: Double] = .init(),
            sensitiveKeys: Set<Metadata.Key> = .init(),
            timestamp: Date = .init()
        ) {
            self.name = name
            self.category = category
            self.message = message
            self.metadata = metadata
            self.metrics = metrics
            self.sensitiveKeys = sensitiveKeys
            self.timestamp = timestamp
        }
        
        private enum CodingKeys: String, CodingKey {
            case name
            case category
            case message
            case metadata
            case metrics
            case timestamp
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(category, forKey: .category)
            try container.encodeIfPresent(message, forKey: .message)
            try container.encode(metadata, forKey: .metadata)
            try container.encode(metrics, forKey: .metrics)
            try container.encode(timestamp, forKey: .timestamp)
        }
    }
}
