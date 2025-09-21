// RequestRouter+Request.swift

import Foundation

extension RequestRouter {
    struct Request: Sendable {
        let key: Key
        let priority: TaskPriority?
        let retryPolicy: RetryPolicy
        let operation: @Sendable () async throws -> Void
        let onCancellation: (@Sendable (CancellationError) -> Void)?
        let onFailure: (@Sendable (Swift.Error) -> Void)?
        let enqueuedAt: ContinuousClock.Instant
        let attempt: Int
        let earliestStart: ContinuousClock.Instant
    }
    
    struct ActiveRequest: Sendable {
        var request: Request
        var task: Task<Void, Never>
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
        public var maximumConcurrentRequests: Int
        public var retryBudget: RetryBudget
        public var backoff: BackoffStrategy
        public var jitterRange: ClosedRange<Double>
        
        public init(minimumDelayBetweenRequests: Duration = .milliseconds(150),
                    maximumConcurrentRequests: Int = 2,
                    retryBudget: RetryBudget = .init(),
                    backoff: BackoffStrategy = .init(),
                    jitterRange: ClosedRange<Double> = 0 ... 0)
        {
            precondition(maximumConcurrentRequests > 0, "maximumConcurrentRequests must be positive")
            precondition(jitterRange.lowerBound >= 0, "Jitter range must be non-negative")
            precondition(jitterRange.upperBound >= jitterRange.lowerBound, "Invalid jitter range")
            self.minimumDelayBetweenRequests = minimumDelayBetweenRequests
            self.maximumConcurrentRequests = maximumConcurrentRequests
            self.retryBudget = retryBudget
            self.backoff = backoff
            self.jitterRange = jitterRange
        }
    }
    
    public struct RetryBudget: Sendable {
        public let maximumRetryCount: Int
        public let replenishmentInterval: Duration
        
        public init(maximumRetryCount: Int = 5,
                    replenishmentInterval: Duration = .seconds(30))
        {
            precondition(maximumRetryCount >= 0, "maximumRetryCount must be non-negative")
            precondition(replenishmentInterval > .zero, "replenishmentInterval must be positive")
            self.maximumRetryCount = maximumRetryCount
            self.replenishmentInterval = replenishmentInterval
        }
        
        func makeState(clock: ContinuousClock) -> State {
            .init(configuration: self, now: clock.now)
        }
        
        struct State: Sendable {
            private let capacity: Double
            private let refillRate: Double
            private var tokens: Double
            private var lastRefill: ContinuousClock.Instant
            
            fileprivate init(configuration: RetryBudget, now: ContinuousClock.Instant) {
                let capacity = Double(configuration.maximumRetryCount)
                self.capacity = capacity
                let replenishment = configuration.replenishmentInterval.secondsDouble
                self.refillRate = capacity / max(replenishment, .leastNonzeroMagnitude)
                self.tokens = capacity
                self.lastRefill = now
            }
            
            mutating func nextDelay(now: ContinuousClock.Instant) -> Duration {
                refill(now: now)
                tokens -= 1
                if tokens >= 0 { return .zero }
                let waitSeconds = (1 - tokens) / max(refillRate, .leastNonzeroMagnitude)
                return .seconds(waitSeconds)
            }
            
            private mutating func refill(now: ContinuousClock.Instant) {
                guard now >= lastRefill else { return }
                let delta = lastRefill.duration(to: now)
                let seconds = delta.secondsDouble
                guard seconds > 0 else { return }
                tokens = min(capacity, tokens + (seconds * refillRate))
                lastRefill = now
            }
        }
    }
    
    public struct BackoffStrategy: Sendable {
        public var initialDelay: Duration
        public var multiplier: Double
        public var maximumDelay: Duration
        
        public init(initialDelay: Duration = .milliseconds(250),
                    multiplier: Double = 2,
                    maximumDelay: Duration = .seconds(10))
        {
            precondition(multiplier >= 1, "multiplier must be at least 1")
            self.initialDelay = initialDelay
            self.multiplier = multiplier
            self.maximumDelay = maximumDelay
        }
        
        public func delay(forAttempt attempt: Int) -> Duration {
            guard attempt > 0 else { return .zero }
            let exponent = Double(max(0, attempt - 1))
            let base = initialDelay.secondsDouble * pow(multiplier, exponent)
            let capped = min(base, maximumDelay.secondsDouble)
            return .seconds(capped)
        }
    }
    
    public enum RetryPolicy: Sendable {
        case retry
        case discard
    }
}
