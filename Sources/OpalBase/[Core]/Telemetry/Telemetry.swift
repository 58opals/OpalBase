// Telemetry.swift

import Foundation

public actor Telemetry {
    public static let shared = Telemetry()
    
    public struct Handler: Sendable {
        public typealias Operation = @Sendable (Event) async throws -> Void
        
        private let operation: Operation
        
        public init(_ operation: @escaping Operation) {
            self.operation = operation
        }
        
        public func callAsFunction(_ event: Event) async throws {
            try await operation(event)
        }
        
        public static func makeConsole(
            printer: @escaping @Sendable (String) -> Void = { message in
                Swift.print(message)
            }
        ) -> Self {
            Handler { event in
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let payload = try encoder.encode(event)
                let json = String(decoding: payload, as: UTF8.self)
                printer(json)
            }
        }
    }
    
    private var isEnabled: Bool
    private var handlers: [Handler]
    private var eventCounters: [EventKey: EventCounter]
    private var valueAggregates: [String: MutableValueAggregate]
    private var recordedErrors: [Error]
    private let redactor = TelemetryRedactor()
    
    public init(
        isEnabled: Bool = false,
        handlers: [Handler] = [.makeConsole()]
    ) {
        self.isEnabled = isEnabled
        self.handlers = handlers
        self.eventCounters = .init()
        self.valueAggregates = .init()
        self.recordedErrors = .init()
    }
    
    public func configure(
        isEnabled: Bool? = nil,
        handlers: [Handler]? = nil
    ) {
        if let isEnabled {
            self.isEnabled = isEnabled
        }
        if let handlers {
            self.handlers = handlers
        }
    }
    
    public func record(
        name: String,
        category: Event.Category,
        message: @autoclosure () -> String? = nil,
        metadata: Metadata = .init(),
        metrics: [String: Double] = .init(),
        sensitiveKeys: Set<Metadata.Key> = .init(),
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
    
    public func record(_ event: Event) async {
        guard isEnabled else { return }
        let sanitised = redactor.sanitise(event: event)
        updateValueAggregates(for: sanitised)
        
        var didRecordFailure = false
        
        for handler in handlers {
            do {
                try await handler(sanitised)
            } catch {
                didRecordFailure = true
                recordedErrors.append(.handlerFailure(description: String(describing: error)))
            }
        }
        
        recordOutcome(for: sanitised, didFail: didRecordFailure)
    }
    
    public func makeMetricsSnapshot(timestamp: Date = .init()) -> MetricsSnapshot {
        MetricsSnapshot(
            timestamp: timestamp,
            eventCounters: eventCounters.reduce(into: .init()) { partialResult, element in
                partialResult[element.key.analyticsKey] = element.value.snapshot
            },
            valueAggregates: valueAggregates.reduce(into: .init()) { partialResult, element in
                partialResult[element.key] = element.value.snapshot
            }
        )
    }
    
    public func collectErrors() -> [Error] {
        let errors = recordedErrors
        recordedErrors.removeAll(keepingCapacity: false)
        return errors
    }
    
    public func reset() {
        eventCounters.removeAll(keepingCapacity: false)
        valueAggregates.removeAll(keepingCapacity: false)
        recordedErrors.removeAll(keepingCapacity: false)
    }
}

extension Telemetry {
    public enum Error: Swift.Error, Sendable {
        case handlerFailure(description: String)
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
    
    func updateValueAggregates(for event: Event) {
        for (metric, value) in event.metrics {
            var aggregate = valueAggregates[metric] ?? MutableValueAggregate()
            aggregate.append(value)
            valueAggregates[metric] = aggregate
        }
    }
    
    func recordOutcome(for event: Event, didFail: Bool) {
        updateCounter(for: event) { counter in
            if didFail {
                counter.recordFailure()
            } else {
                counter.recordSuccess()
            }
        }
    }
    
    func updateCounter(for event: Event, applying update: (inout EventCounter) -> Void) {
        let key = EventKey(category: event.category, name: event.name)
        var counter = eventCounters[key] ?? EventCounter()
        update(&counter)
        eventCounters[key] = counter
    }
}
