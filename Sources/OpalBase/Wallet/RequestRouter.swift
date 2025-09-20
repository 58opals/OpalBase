// RequestRouter.swift

import Foundation

public actor RequestRouter<RequestValue: Hashable & Sendable> {
    public struct Key<RawValue: Hashable & Sendable>: Hashable, Sendable {
        private let rawValue: RawValue
        
        public init(_ rawValue: RawValue) {
            self.rawValue = rawValue
        }
    }
    
    public struct Configuration: Sendable {
        public var minimumDelayBetweenRequests: Duration
        
        public init(minimumDelayBetweenRequests: Duration = .milliseconds(150)) {
            self.minimumDelayBetweenRequests = minimumDelayBetweenRequests
        }
    }
    
    public enum RetryPolicy: Sendable {
        case retry
        case discard
    }
    
    public struct Handle<RawValue: Hashable & Sendable>: Sendable {
        private let router: RequestRouter
        public let key: Key<RawValue>
        
        private init(router: RequestRouter, key: Key<RawValue>) {
            self.router = router
            self.key = key
        }
    }
    
    private struct Request<RawValue: Hashable & Sendable>: Sendable {
        let key: Key<RawValue>
        let priority: TaskPriority?
        let retryPolicy: RetryPolicy
        let operation: @Sendable () async throws -> Void
    }
    
    private struct ActiveRequest<RawValue: Hashable & Sendable>: Sendable {
        var request: Request<RawValue>
        var task: Task<Void, Swift.Error>
        var replacement: Request<RawValue>?
    }
    
    private let configuration: Configuration
    private var queue: [Request<RequestValue>] = .init()
    private var queuedIndices: [Key<RequestValue>: Int] = .init()
    private var activeRequests: [Key<RequestValue>: ActiveRequest<RequestValue>] = .init()
    private var processor: Task<Void, Never>?
    private var isSuspended = false
    private let clock = ContinuousClock()
    private var nextPermittedStart: ContinuousClock.Instant?
    
    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }
}
