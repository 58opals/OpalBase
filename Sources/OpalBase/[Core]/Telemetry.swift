// Telemetry.swift

import Foundation

/// A configurable telemetry pipeline that aggregates metrics, redacts sensitive payloads,
/// and emits structured analytics events.
///
/// The pipeline replaces the previous `Log` actor with a richer interface while preserving
/// the ability to fire-and-forget diagnostic messages. All events are sanitised before
/// reaching any sink so analytics consumers never observe raw user data.
///
/// ## Example
/// ```swift
/// await Telemetry.shared.record(
///     name: "wallet.transaction.submitted",
///     category: .wallet,
///     message: "Submitted transaction to network",
///     metadata: [
///         "transaction.identifier": .string(transactionID),
///         "fee.satoshis": .int(fee)
///     ],
///     sensitiveKeys: ["transaction.identifier"]
/// )
/// ```
///
/// ## Migration
/// Replace usages of `Log.shared.log("message")` with
/// `await Telemetry.shared.record(name:category:message:)`. Supplying a dedicated event
/// name enables richer aggregation and ensures the redactor can strip sensitive tokens.
public actor Telemetry {
    public static let shared = Telemetry()
    
    private var isEnabled: Bool
    private var sinks: [any TelemetrySink]
    private var eventCounters: [EventKey: EventCounter]
    private var valueAggregates: [String: MutableValueAggregate]
    private var recordedErrors: [Error]
    private let redactor = TelemetryRedactor()
    
    /// Creates a telemetry pipeline with optional sinks.
    /// - Parameters:
    ///   - isEnabled: Indicates whether events should be processed.
    ///   - sinks: Destinations that should consume sanitised events. Defaults to a
    ///            structured console sink suitable for development diagnostics.
    public init(
        isEnabled: Bool = false,
        sinks: [any TelemetrySink] = [TelemetryStructuredConsoleSink()]
    ) {
        self.isEnabled = isEnabled
        self.sinks = sinks
        self.eventCounters = [:]
        self.valueAggregates = [:]
        self.recordedErrors = []
    }
    
    /// Updates the configuration of the telemetry pipeline.
    /// - Parameters:
    ///   - isEnabled: Optional override for the enabled flag.
    ///   - sinks: Optional replacement sinks. When provided, the array replaces the existing sinks.
    public func configure(
        isEnabled: Bool? = nil,
        sinks: [any TelemetrySink]? = nil
    ) {
        if let isEnabled {
            self.isEnabled = isEnabled
        }
        if let sinks {
            self.sinks = sinks
        }
    }
    
    /// Records an event using the supplied components.
    /// - Parameters:
    ///   - name: A unique identifier for the event. Event names are used for aggregation keys.
    ///   - category: A semantic grouping for the event that can be leveraged in analytics tools.
    ///   - message: Optional human-friendly description. Sensitive tokens will be redacted.
    ///   - metadata: Structured metadata that supports redaction at key granularity.
    ///   - metrics: Numeric metrics associated with the event.
    ///   - sensitiveKeys: Metadata keys that should be replaced by a redaction token.
    ///   - timestamp: Overrides the automatically generated timestamp.
    public func record(
        name: String,
        category: Event.Category,
        message: @autoclosure () -> String? = nil,
        metadata: Metadata = [:],
        metrics: [String: Double] = [:],
        sensitiveKeys: Set<Metadata.Key> = [],
        timestamp: Date = .init()
    ) async {
        let event = Event(
            name: name,
            category: category,
            message: message(),
            metadata: metadata,
            metrics: metrics,
            sensitiveKeys: sensitiveKeys,
            timestamp: timestamp
        )
        await record(event)
    }
    
    /// Records an already constructed event.
    /// - Parameter event: The event that should be processed by the pipeline.
    public func record(_ event: Event) async {
        guard isEnabled else { return }
        let sanitised = redactor.sanitise(event: event)
        updateValueAggregates(for: sanitised)
        
        var didRecordFailure = false
        
        for sink in sinks {
            do {
                try await sink.consume(sanitised)
            } catch {
                if !didRecordFailure {
                    registerFailure(for: sanitised)
                    didRecordFailure = true
                }
                recordedErrors.append(.sinkFailure(description: String(describing: error)))
            }
        }
        
        if !didRecordFailure {
            registerSuccess(for: sanitised)
        }
    }
    
    /// Generates a snapshot of the aggregated metrics for analytics inspection.
    /// - Returns: A snapshot containing counters for events and value aggregates.
    public func metricsSnapshot(timestamp: Date = .init()) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: timestamp,
            eventCounters: eventCounters.reduce(into: [:]) { partialResult, element in
                partialResult[element.key.analyticsKey] = element.value.snapshot
            },
            valueAggregates: valueAggregates.reduce(into: [:]) { partialResult, element in
                partialResult[element.key] = element.value.snapshot
            }
        )
    }
    
    /// Collects errors produced by telemetry sinks and clears the internal buffer.
    /// This enables callers to react to sink failures without leaking implementation details.
    /// - Returns: The errors raised by sinks since the last invocation.
    public func collectErrors() -> [Error] {
        let errors = recordedErrors
        recordedErrors.removeAll(keepingCapacity: false)
        return errors
    }
    
    /// Resets all aggregated counters, metrics, and recorded errors.
    /// Typically useful in tests or when restarting analytics sessions.
    public func reset() {
        eventCounters.removeAll(keepingCapacity: false)
        valueAggregates.removeAll(keepingCapacity: false)
        recordedErrors.removeAll(keepingCapacity: false)
    }
}

extension Telemetry {
    /// A telemetry event capturing structured metadata and numeric metrics.
    public struct Event: Sendable, Encodable {
        /// Semantic category describing the type of event.
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
            metadata: Metadata = [:],
            metrics: [String: Double] = [:],
            sensitiveKeys: Set<Metadata.Key> = [],
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

extension Telemetry {
    /// Errors generated by the telemetry subsystem.
    public enum Error: Swift.Error, Sendable {
        case sinkFailure(description: String)
    }
}

extension Telemetry {
    /// Encapsulates metadata associated with telemetry events.
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
        
        public init(_ storage: [Key: MetadataValue] = [:]) {
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
    /// Supported metadata value types for telemetry events.
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

extension Telemetry {
    /// Snapshot produced by `metricsSnapshot()` containing aggregated analytics data.
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

// MARK: - Telemetry internals

private extension Telemetry {
    struct EventKey: Hashable, Sendable {
        let category: Event.Category
        let name: String
        
        var analyticsKey: String { "\(category.rawValue).\(name)" }
    }
    
    struct EventCounter: Sendable {
        var total: Int = 0
        var failures: Int = 0
        
        mutating func recordSuccess() {
            total &+= 1
        }
        
        mutating func recordFailure() {
            total &+= 1
            failures &+= 1
        }
        
        var snapshot: MetricsSnapshot.EventCounters {
            MetricsSnapshot.EventCounters(total: total, failures: failures)
        }
    }
    
    struct MutableValueAggregate: Sendable {
        private(set) var count: Int = 0
        private(set) var sum: Double = 0
        private(set) var minimum: Double = .infinity
        private(set) var maximum: Double = -.infinity
        
        mutating func append(_ value: Double) {
            count &+= 1
            sum += value
            minimum = Swift.min(minimum, value)
            maximum = Swift.max(maximum, value)
        }
        
        var snapshot: MetricsSnapshot.ValueAggregate {
            MetricsSnapshot.ValueAggregate(
                count: count,
                sum: sum,
                minimum: count > 0 ? minimum : nil,
                maximum: count > 0 ? maximum : nil
            )
        }
    }
    
    func registerSuccess(for event: Event) {
        let key = EventKey(category: event.category, name: event.name)
        var counter = eventCounters[key] ?? EventCounter()
        counter.recordSuccess()
        eventCounters[key] = counter
    }
    
    func registerFailure(for event: Event) {
        let key = EventKey(category: event.category, name: event.name)
        var counter = eventCounters[key] ?? EventCounter()
        counter.recordFailure()
        eventCounters[key] = counter
    }
    
    func updateValueAggregates(for event: Event) {
        for (metric, value) in event.metrics {
            var aggregate = valueAggregates[metric] ?? MutableValueAggregate()
            aggregate.append(value)
            valueAggregates[metric] = aggregate
        }
    }
}

// MARK: - Telemetry sinks

/// A sink that emits redacted telemetry events as structured JSON to the console.
public struct TelemetryStructuredConsoleSink: TelemetrySink {
    public init() {}
    
    public func consume(_ event: Telemetry.Event) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(event)
        let json = String(decoding: payload, as: UTF8.self)
        print(json)
    }
}

// MARK: - Telemetry redaction

struct TelemetryRedactor: Sendable {
    enum Constants {
        static let redactedToken = "‹redacted›"
    }
    
    func sanitise(event: Telemetry.Event) -> Telemetry.Event {
        var sanitised = event
        if let message = event.message {
            sanitised.message = sanitise(message: message)
        }
        sanitised.metadata = sanitise(metadata: event.metadata, sensitiveKeys: event.sensitiveKeys)
        return sanitised
    }
    
    private func sanitise(message: String) -> String {
        let segments = message.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !segments.isEmpty else { return message }
        return segments.map { token -> String in
            let trimmed = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard !trimmed.isEmpty else { return token }
            guard shouldRedact(token: trimmed) else { return token }
            return token.replacingOccurrences(of: trimmed, with: Constants.redactedToken)
        }.joined(separator: " ")
    }
    
    private func sanitise(
        metadata: Telemetry.Metadata,
        sensitiveKeys: Set<Telemetry.Metadata.Key>
    ) -> Telemetry.Metadata {
        var sanitised = metadata
        for key in metadata.keys {
            if sensitiveKeys.contains(key) {
                sanitised[key] = .redacted
                continue
            }
            if case .string(let value)? = metadata[key], shouldRedact(token: value) {
                sanitised[key] = .redacted
            }
        }
        return sanitised
    }
    
    private func shouldRedact(token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.count >= 8 && trimmed.isLikelyHexadecimal { return true }
        var digitCount = 0
        for character in trimmed where character.isNumber {
            digitCount += 1
        }
        if digitCount >= 6 { return true }
        if trimmed.contains(where: { !$0.isAlphaNumeric }) && trimmed.count >= 12 { return true }
        return false
    }
}

// MARK: - Protocols

/// Consumers that receive sanitised telemetry events for downstream processing.
public protocol TelemetrySink: Sendable {
    func consume(_ event: Telemetry.Event) async throws
}

private extension String {
    var isLikelyHexadecimal: Bool {
        guard !isEmpty else { return false }
        return allSatisfy { $0.isHexDigit }
    }
}

private extension Character {
    var isAlphaNumeric: Bool {
        unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
    
    var isHexDigit: Bool {
        unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }
}
