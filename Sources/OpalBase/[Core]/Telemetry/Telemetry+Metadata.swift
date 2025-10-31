// Telemetry+Metadata.swift

import Foundation

extension Telemetry {
    public struct Metadata: Sendable, Encodable, ExpressibleByDictionaryLiteral {
        public struct Key: Hashable, Sendable, ExpressibleByStringLiteral, Encodable {
            public let rawValue: String
            
            public init(_ rawValue: String) {
                self.rawValue = rawValue
            }
            
            public init(stringLiteral value: String) {
                self.rawValue = value
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(rawValue)
            }
        }
        
        private var storage: [Key: MetadataValue]
        
        public init(dictionaryLiteral elements: (Key, MetadataValue)...) {
            self.storage = Dictionary(elements, uniquingKeysWith: { first, _ in first })
        }
        
        public init(_ storage: [Key: MetadataValue] = .init()) {
            self.storage = storage
        }
        
        public subscript(key: Key) -> MetadataValue? {
            get { storage[key] }
            set { storage[key] = newValue }
        }
        
        public var keys: [Key] { Array(storage.keys) }
        
        public var isEmpty: Bool { storage.isEmpty }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in storage {
                try container.encode(value, forKey: DynamicCodingKey(stringValue: key.rawValue))
            }
        }
        
        fileprivate var rawDictionary: [Key: MetadataValue] { storage }
    }
}

extension Telemetry.Metadata {
    struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        
        init(stringValue: String) {
            self.stringValue = stringValue
        }
        
        init?(intValue: Int) {
            return nil
        }
    }
}

extension Telemetry {
    public enum MetadataValue: Sendable, Encodable, Equatable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case null
        case redacted
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value):
                try container.encode(value)
            case .int(let value):
                try container.encode(value)
            case .double(let value):
                try container.encode(value)
            case .bool(let value):
                try container.encode(value)
            case .null:
                try container.encodeNil()
            case .redacted:
                try container.encode(TelemetryRedactor.Constants.redactedToken)
            }
        }
    }
}
