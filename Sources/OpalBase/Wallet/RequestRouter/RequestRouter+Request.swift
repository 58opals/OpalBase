// RequestRouter+Request.swift

import Foundation

extension RequestRouter {
    struct Request: Sendable {
        let key: Key
        let priority: TaskPriority?
        let retryPolicy: RetryPolicy
        let operation: @Sendable () async throws -> Void
        let onCancellation: (@Sendable (CancellationError) -> Void)?
    }
    
    struct ActiveRequest: Sendable {
        var request: Request
        var task: Task<Void, Swift.Error>
        var replacement: Request?
    }
    
    public struct Key: Hashable, Sendable {
        let rawValue: RequestValue
        
        init(rawValue: RequestValue) {
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
}
