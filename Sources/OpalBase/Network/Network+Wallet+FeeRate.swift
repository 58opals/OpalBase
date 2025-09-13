// Network+Wallet+FeeRate.swift

import Foundation

extension Network.Wallet {
    public actor FeeRate {
        private let fulcrumPool: Network.Wallet.FulcrumPool
        private let cacheThreshold: TimeInterval
        private var cachedRates: [Tier: CachedRate] = .init()
        
        public init(fulcrumPool: Network.Wallet.FulcrumPool, cacheThreshold: TimeInterval = 10 * 60) {
            self.fulcrumPool = fulcrumPool
            self.cacheThreshold = cacheThreshold
        }
        
        func fetchFeeRate(for tier: Tier) async throws -> UInt64 {
            let fulcrum = try await fulcrumPool.acquireFulcrum()
            
            let estimated = try await Transaction.estimateFee(numberOfBlocks: tier.targetBlocks, using: fulcrum)
            let relay = try await Transaction.relayFee(using: fulcrum)
            
            return max(estimated.uint64, relay.uint64)
        }
        
        func fetchRecommendedFeeRate(for tier: Tier = .fast) async throws -> UInt64 {
            if let cached = cachedRates[tier], cached.isValid(for: cacheThreshold) {
                return cached.value
            }
            
            let rate = try await fetchFeeRate(for: tier)
            cachedRates[tier] = CachedRate(value: rate, timestamp: .now)
            return rate
        }
    }
}

extension Network.Wallet.FeeRate {
    enum Tier: Sendable {
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
    }
    
    struct CachedRate {
        let value: UInt64
        let timestamp: Date
        
        func isValid(for threshold: TimeInterval) -> Bool {
            Date().timeIntervalSince(timestamp) < threshold
        }
    }
}
