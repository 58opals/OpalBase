// Network+Telemetry+Emitter.swift

import Foundation

extension Network.Telemetry {
    public actor Emitter {
        public var policy: Privacy
        private var sink: Sink?
        private var buffer: [Event] = []
        private var windowStart: Date = .now
        private var eventsInWindow: Int = 0
        
        public init(policy: Privacy = .init(), sink: Sink? = nil) {
            self.policy = policy
            self.sink = sink
        }
        
        public func emit(_ event: Event) async throws {
            let now = Date()
            if now.timeIntervalSince(windowStart) > policy.rateInterval {
                windowStart = now
                eventsInWindow = 0
            }
            guard eventsInWindow < policy.rateCap else {
                throw Network.Telemetry.Error.rateLimitExceeded
            }
            eventsInWindow += 1
            buffer.append(event)
            if buffer.count >= policy.batchSize {
                try await flush()
            }
        }
        
        public func flush() async throws {
            guard !buffer.isEmpty else { return }
            let batch = buffer
            buffer.removeAll()
            try await Task.sleep(nanoseconds: policy.jitterDelay())
            try await sink?.send(batch: batch)
        }
    }
}

extension Network.Telemetry {
    public enum Error: Swift.Error, Sendable {
        case rateLimitExceeded
    }
}

extension Network.Telemetry {
    public protocol Sink: Sendable {
        func send(batch: [Event]) async throws
    }
    
    public struct Event: Sendable, Codable {
        public var name: String
        public var attributes: [String: String]
        
        public init(name: String, attributes: [String: String] = [:]) {
            self.name = name
            self.attributes = attributes
        }
    }
}
