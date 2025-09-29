// Network+Wallet+FeeRate.swift

import Foundation

extension Network.Wallet {
    public actor FeeRate: FeeService {
        public typealias RateProvider = @Sendable (Tier) async throws -> UInt64
        
        private let fetchRate: RateProvider
        private let cacheThreshold: TimeInterval
        private let smoothingFactor: Double
        private let persistenceWindow: TimeInterval
        private let persistence: Persistence
        
        private var cachedRates: [Tier: CachedRate] = .init()
        
        public init(connectionPool: any Network.Wallet.ConnectionPool,
                    cacheThreshold: TimeInterval = 10 * 60,
                    smoothingAlpha: Double = 0.35,
                    persistenceWindow: TimeInterval = 60 * 60,
                    feeRepository: Storage.Repository.Fees? = nil,
                    persistence: Persistence? = nil)
        {
            self.fetchRate = { tier in
                let gateway = try await connectionPool.acquireGateway()
                async let estimated = gateway.getEstimateFee(targetBlocks: tier.targetBlocks)
                async let relay = gateway.getRelayFee()
                let (recommended, relayFee) = try await (estimated, relay)
                return max(recommended.uint64, relayFee.uint64)
            }
            self.cacheThreshold = cacheThreshold
            self.smoothingFactor = Self.clamp(smoothingAlpha)
            self.persistenceWindow = max(0, persistenceWindow)
            if let persistence {
                self.persistence = persistence
            } else if let feeRepository {
                self.persistence = .storage(repository: feeRepository)
            } else {
                self.persistence = .noop
            }
        }
        
        public init(rateProvider: @escaping RateProvider,
                    cacheThreshold: TimeInterval = 10 * 60,
                    smoothingAlpha: Double = 0.35,
                    persistenceWindow: TimeInterval = 60 * 60,
                    feeRepository: Storage.Repository.Fees? = nil,
                    persistence: Persistence? = nil)
        {
            self.fetchRate = rateProvider
            self.cacheThreshold = cacheThreshold
            self.smoothingFactor = Self.clamp(smoothingAlpha)
            self.persistenceWindow = max(0, persistenceWindow)
            if let persistence {
                self.persistence = persistence
            } else if let feeRepository {
                self.persistence = .storage(repository: feeRepository)
            } else {
                self.persistence = .noop
            }
        }
        
        public func fetchRecommendedFeeRate(for tier: Tier = .fast) async throws -> UInt64 {
            if let cached = cachedRates[tier], cached.isValid(for: cacheThreshold) {
                return cached.value
            }
            
            do {
                let measurement = try await fetchRate(tier)
                let smoothed = try await smooth(measurement: measurement, for: tier)
                let cached = CachedRate(value: smoothed, timestamp: Date())
                cachedRates[tier] = cached
                try await persist(rate: smoothed, for: tier)
                return smoothed
            } catch {
                if let fallback = try await baselineRate(for: tier) {
                    let cached = CachedRate(value: fallback, timestamp: Date())
                    cachedRates[tier] = cached
                    return fallback
                }
                throw error
            }
        }
        
        private func smooth(measurement: UInt64, for tier: Tier) async throws -> UInt64 {
            guard smoothingFactor > 0 else { return measurement }
            guard let baseline = try await baselineRate(for: tier) else { return measurement }
            let weighted = (Double(measurement) * smoothingFactor) + (Double(baseline) * (1 - smoothingFactor))
            let rounded = UInt64(weighted.rounded(.toNearestOrAwayFromZero))
            return rounded
        }
        
        private func baselineRate(for tier: Tier) async throws -> UInt64? {
            if let cached = cachedRates[tier] {
                return cached.value
            }
            return try await persistence.load(tier: tier, maxAge: persistenceWindow)
        }
        
        private func persist(rate: UInt64, for tier: Tier) async throws {
            try await persistence.store(tier: tier, value: rate, ttl: persistenceWindow)
        }
        
        private static func clamp(_ value: Double) -> Double {
            if value.isNaN { return 0 }
            return min(1, max(0, value))
        }
    }
}

extension Network.Wallet.FeeRate {
    public enum Tier: Hashable, Sendable {
        case slow
        case normal
        case fast
        
        var targetBlocks: Int {
            switch self {
            case .slow: return 18
            case .normal: return 6
            case .fast: return 1
            }
        }
        
        var storageTier: Storage.Entity.FeeModel.Tier {
            switch self {
            case .slow: return .slow
            case .normal: return .normal
            case .fast: return .fast
            }
        }
    }
    
    struct CachedRate {
        let value: UInt64
        let timestamp: Date
        
        func isValid(for threshold: TimeInterval) -> Bool {
            guard threshold > 0 else { return false }
            return Date().timeIntervalSince(timestamp) < threshold
        }
    }
}
