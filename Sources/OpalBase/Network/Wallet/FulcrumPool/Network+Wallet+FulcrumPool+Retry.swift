// Network+Wallet+FulcrumPool+Retry.swift

import Foundation

extension Network.Wallet.FulcrumPool {
    public struct Retry: Sendable {
        private let capacity: Double
        private let spacing: TimeInterval
        private let baselineTokens: Double
        private var tokens: Double
        private var warmupAllowance: Int
        private var lastRefill: Date
        
        init(configuration: Configuration.Budget, now: Date = .init()) {
            let capacity = max(1, Double(configuration.maximumAttempts - 1))
            self.capacity = capacity
            self.spacing = configuration.replenishmentInterval / capacity
            if configuration.maximumAttempts >= 2 {
                let baseline = max(1, capacity - 1)
                self.baselineTokens = baseline
                self.tokens = baseline
            } else {
                let baseline = max(0, capacity - 1)
                self.baselineTokens = baseline
                self.tokens = baseline
            }
            self.warmupAllowance = 1
            self.lastRefill = now
        }
        
        mutating func nextDelay(now: Date) -> TimeInterval {
            refill(now: now)
            if warmupAllowance > 0 {
                warmupAllowance -= 1
                return 0
            }
            
            if tokens >= 1 {
                tokens -= 1
                return 0
            }
            
            let deficit = 1 - tokens
            let wait = deficit * spacing
            tokens = 0
            lastRefill = now
            return max(0, wait)
        }
        
        mutating func reset(now: Date) {
            tokens = baselineTokens
            warmupAllowance = 1
            lastRefill = now
        }
        
        private mutating func refill(now: Date) {
            guard now >= lastRefill else { return }
            let delta = now.timeIntervalSince(lastRefill)
            guard delta > 0 else { return }
            tokens = min(capacity, tokens + (delta / spacing))
            lastRefill = now
        }
    }
}

extension Network.Wallet.FulcrumPool.Retry {
    public struct Configuration: Sendable {
        public struct Budget: Sendable {
            public let maximumAttempts: Int
            public let replenishmentInterval: TimeInterval
            
            public init(maximumAttempts: Int, replenishmentInterval: TimeInterval) {
                precondition(maximumAttempts > 0, "maximumAttempts must be positive.")
                precondition(replenishmentInterval > 0, "replenishmentInterval must be positive.")
                self.maximumAttempts = maximumAttempts
                self.replenishmentInterval = replenishmentInterval
            }
        }
        
        public let perServer: Budget
        public let global: Budget
        public let jitter: ClosedRange<TimeInterval>
        
        public init(perServer: Budget,
                    global: Budget,
                    jitter: ClosedRange<TimeInterval> = 0 ... 0.75) {
            precondition(jitter.lowerBound >= 0, "jitter must be non-negative.")
            precondition(jitter.upperBound >= jitter.lowerBound, "jitter range is invalid.")
            
            self.perServer = perServer
            self.global = global
            self.jitter = jitter
        }
        
        public static let standard: Self = .init(perServer: .init(maximumAttempts: 5,
                                                                  replenishmentInterval: 45),
                                                 global: .init(maximumAttempts: 12,
                                                               replenishmentInterval: 30),
                                                 jitter: 0 ... 0.75)
    }
}
