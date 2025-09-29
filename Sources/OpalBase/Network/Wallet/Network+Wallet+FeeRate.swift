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
                    persistence: Persistence? = nil) {
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
                    persistence: Persistence? = nil) {
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
            let now = Date()
            if let cached = cachedRates[tier], cached.isFresh(for: cacheThreshold, now: now) {
                return cached.value
            }
            
            do {
                let measurement = try await fetchRate(tier)
                let smoothed = try await smooth(measurement: measurement, for: tier)
                let persisted = try await persist(rate: smoothed, for: tier)
                cachedRates[tier] = persisted
                return persisted.value
            } catch {
                if let baseline = try await baselineRate(for: tier, now: now) {
                    cachedRates[tier] = baseline
                    return baseline.value
                }
                
                if let fallback = try await fallbackBaseline(for: tier, now: now) {
                    cachedRates[tier] = fallback
                    return fallback.value
                }
                
                throw error
            }
        }
        
        public func record(event: Event) async throws {
            try await purgeExpiredRates(now: event.timestamp)
        }
        
        private func smooth(measurement: UInt64, for tier: Tier) async throws -> UInt64 {
            guard smoothingFactor > 0 else { return measurement }
            guard let baseline = try await baselineRate(for: tier, now: Date()) else { return measurement }
            let weighted = (Double(measurement) * smoothingFactor) + (Double(baseline.value) * (1 - smoothingFactor))
            let rounded = UInt64(weighted.rounded(.toNearestOrAwayFromZero))
            return rounded
        }
        
        private func baselineRate(for tier: Tier, now: Date) async throws -> CachedRate? {
            if let cached = cachedRates[tier] {
                if cached.isWithin(window: persistenceWindow, now: now) {
                    return cached
                }
                
                cachedRates.removeValue(forKey: tier)
                if let version = cached.version {
                    do {
                        try await persistence.invalidate(tier: tier, expectedVersion: version)
                    } catch let error as Persistence.Error {
                        if case .repository = error { throw error }
                    }
                }
            }
            
            guard persistenceWindow > 0 else { return nil }
            guard let snapshot = try await persistence.load(tier: tier, maxAge: persistenceWindow) else {
                return nil
            }
            
            let cached = CachedRate(snapshot: snapshot, target: tier)
            cachedRates[tier] = cached
            return cached
        }
        
        private func fallbackBaseline(for tier: Tier, now: Date) async throws -> CachedRate? {
            for alternative in tier.fallbackCandidates {
                if let baseline = try await baselineRate(for: alternative, now: now) {
                    let promoted = baseline.promoted(to: tier)
                    cachedRates[tier] = promoted
                    return promoted
                }
            }
            return nil
        }
        
        private func persist(rate: UInt64, for tier: Tier) async throws -> CachedRate {
            let now = Date()
            guard persistenceWindow > 0 else {
                return CachedRate(tier: tier,
                                  value: rate,
                                  timestamp: now,
                                  version: nil,
                                  source: tier)
            }
            
            do {
                let snapshot = try await persistence.store(tier: tier,
                                                           value: rate,
                                                           ttl: persistenceWindow,
                                                           expectedVersion: cachedRates[tier]?.version)
                return CachedRate(snapshot: snapshot, target: tier)
            } catch let error as Persistence.Error {
                switch error {
                case let .conflict(_, actual):
                    if let resolved = try await resolveConflict(for: tier,
                                                                value: rate,
                                                                actualVersion: actual) {
                        return resolved
                    }
                    throw error
                case .repository:
                    throw error
                }
            }
        }
        
        private func resolveConflict(for tier: Tier,
                                     value: UInt64,
                                     actualVersion: UInt64?) async throws -> CachedRate?
        {
            guard persistenceWindow > 0 else { return nil }
            
            var attempt = 0
            var latestVersion = actualVersion
            
            while attempt < 3 {
                guard let snapshot = try await persistence.load(tier: tier, maxAge: persistenceWindow) else {
                    return nil
                }
                
                let expected = latestVersion ?? snapshot.version
                do {
                    let updated = try await persistence.store(tier: tier,
                                                              value: value,
                                                              ttl: persistenceWindow,
                                                              expectedVersion: expected)
                    return CachedRate(snapshot: updated, target: tier)
                } catch let conflict as Persistence.Error {
                    if case let .conflict(_, actual) = conflict {
                        latestVersion = actual
                        attempt += 1
                        continue
                    }
                    throw conflict
                }
            }
            
            return nil
        }
        
        private func purgeExpiredRates(now: Date) async throws {
            guard cacheThreshold > 0 || persistenceWindow > 0 else { return }
            
            var expired: [Tier: CachedRate] = .init()
            for (tier, cached) in cachedRates {
                let cacheExpired = cacheThreshold > 0 && !cached.isFresh(for: cacheThreshold, now: now)
                let persistenceExpired = persistenceWindow > 0 && !cached.isWithin(window: persistenceWindow, now: now)
                if cacheExpired || persistenceExpired {
                    expired[tier] = cached
                    cachedRates.removeValue(forKey: tier)
                }
            }
            
            guard persistenceWindow > 0 else { return }
            
            for (tier, cached) in expired {
                guard let version = cached.version else { continue }
                do {
                    try await persistence.invalidate(tier: tier, expectedVersion: version)
                } catch let error as Persistence.Error {
                    if case .repository = error { throw error }
                }
            }
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
        
        var fallbackCandidates: [Tier] {
            switch self {
            case .fast:
                return [.normal, .slow]
            case .normal:
                return [.fast, .slow]
            case .slow:
                return [.normal, .fast]
            }
        }
    }
    
    public enum Event: Sendable, Equatable {
        case headersPinged(Date)
        case mempoolRefreshed(Date)
        
        var timestamp: Date {
            switch self {
            case let .headersPinged(date):
                return date
            case let .mempoolRefreshed(date):
                return date
            }
        }
    }
    
    struct CachedRate: Sendable, Equatable {
        let tier: Tier
        let value: UInt64
        let timestamp: Date
        
        let version: UInt64?
        let source: Tier
        
        init(tier: Tier, value: UInt64, timestamp: Date, version: UInt64?, source: Tier) {
            self.tier = tier
            self.value = value
            self.timestamp = timestamp
            self.version = version
            self.source = source
        }
        
        init(snapshot: Persistence.Snapshot, target: Tier) {
            self.init(tier: target,
                      value: snapshot.value,
                      timestamp: snapshot.timestamp,
                      version: snapshot.version,
                      source: snapshot.tier)
        }
        
        func isFresh(for threshold: TimeInterval, now: Date) -> Bool {
            guard threshold > 0 else { return false }
            return now.timeIntervalSince(timestamp) < threshold
        }
        
        func isWithin(window: TimeInterval, now: Date) -> Bool {
            guard window > 0 else { return false }
            return now.timeIntervalSince(timestamp) <= window
        }
        
        func promoted(to target: Tier) -> CachedRate {
            .init(tier: target,
                  value: value,
                  timestamp: timestamp,
                  version: nil,
                  source: source)
        }
    }
}
