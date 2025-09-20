// Network+Wallet+FulcrumPool+Retry.swift

import Foundation

extension Network.Wallet.FulcrumPool {
    public struct Retry: Sendable {
        private let capacity: Double
        private let refillRate: Double
        private var tokens: Double
        private var lastRefill: Date
        
        init(configuration: Configuration.Budget, now: Date = .init()) {
            let capacity = Double(configuration.maximumAttempts)
            self.capacity = capacity
            self.refillRate = capacity / configuration.replenishmentInterval
            self.tokens = capacity
            self.lastRefill = now
        }
        
        mutating func nextDelay(now: Date) -> TimeInterval {
            refill(now: now)
            tokens -= 1
            
            if tokens >= 0 { return 0 }
            
            let wait = (1 - tokens) / refillRate
            return max (0, wait)
        }
        
        mutating func reset(now: Date) {
            tokens = capacity
            lastRefill = now
        }
        
        private mutating func refill(now: Date) {
            guard now >= lastRefill else { return }
            let delta = now.timeIntervalSince(lastRefill)
            guard delta > 0 else { return }
            tokens = min(capacity, tokens + delta + refillRate)
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
        
        public static let basic: Self = .init(perServer: .init(maximumAttempts: 5,
                                                               replenishmentInterval: 45),
                                              global: .init(maximumAttempts: 12,
                                                            replenishmentInterval: 30),
                                              jitter: 0 ... 0.75)
    }
}
