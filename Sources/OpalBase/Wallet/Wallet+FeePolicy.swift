// Wallet+FeePolicy.swift

import Foundation

extension Wallet {
    public struct FeePolicy: Sendable {
        public enum Preference: String, Codable, Sendable, CaseIterable {
            case economy
            case standard
            case priority
            
            var defaultTargetConfirmationBlocks: Int {
                switch self {
                case .economy:
                    return 12
                case .standard:
                    return 6
                case .priority:
                    return 2
                }
            }
        }
        
        public struct NetworkConditions: Sendable {
            private let recommendedRates: [Preference: UInt64]
            private let fallbackRate: UInt64?
            
            public init(recommendedRates: [Preference: UInt64] = .init(), fallbackRate: UInt64? = nil) {
                self.recommendedRates = recommendedRates
                self.fallbackRate = fallbackRate
            }
            
            func rate(for preference: Preference) -> UInt64? {
                if let preferenceRate = recommendedRates[preference] {
                    return preferenceRate
                }
                return fallbackRate
            }
        }
        
        public struct RecommendationContext: Sendable {
            public var targetConfirmationBlocks: Int?
            public var networkConditions: NetworkConditions?
            
            public init(targetConfirmationBlocks: Int? = nil, networkConditions: NetworkConditions? = nil) {
                self.targetConfirmationBlocks = targetConfirmationBlocks
                self.networkConditions = networkConditions
            }
        }
        
        public struct Override: Sendable {
            public var explicitFeeRate: UInt64?
            public var preference: Preference?
            public var targetConfirmationBlocks: Int?
            
            public init(explicitFeeRate: UInt64? = nil,
                        preference: Preference? = nil,
                        targetConfirmationBlocks: Int? = nil) {
                self.explicitFeeRate = explicitFeeRate
                self.preference = preference
                self.targetConfirmationBlocks = targetConfirmationBlocks
            }
            
            func applyExplicitFeeRate(explicitFeeRate: UInt64) -> Override {
                Override(explicitFeeRate: explicitFeeRate,
                         preference: preference,
                         targetConfirmationBlocks: targetConfirmationBlocks)
            }
        }
        
        public struct EstimatorContext: Sendable {
            public var targetConfirmationBlocks: Int
            public var preference: Preference
            public var networkConditions: NetworkConditions?
            
            public init(targetConfirmationBlocks: Int,
                        preference: Preference,
                        networkConditions: NetworkConditions? = nil) {
                self.targetConfirmationBlocks = targetConfirmationBlocks
                self.preference = preference
                self.networkConditions = networkConditions
            }
        }
        
        public typealias FeeEstimator = @Sendable (EstimatorContext) -> UInt64?
        
        private let defaultFeeRate: UInt64
        private let preference: Preference
        private let estimator: FeeEstimator?
        
        public init(defaultFeeRate: UInt64 = Transaction.defaultFeeRate,
                    preference: Preference = .economy,
                    estimator: FeeEstimator? = nil) {
            self.defaultFeeRate = defaultFeeRate
            self.preference = preference
            self.estimator = estimator
        }
        
        public func recommendFeeRate(for context: RecommendationContext = .init(),
                                     override: Override? = nil) -> UInt64 {
            if let explicitFeeRate = override?.explicitFeeRate {
                return explicitFeeRate
            }
            
            let effectivePreference = override?.preference ?? preference
            let targetBlocks = resolveTargetBlocks(preference: effectivePreference,
                                                   context: context,
                                                   override: override)
            
            if let estimator, let targetBlocks {
                let estimatorContext = EstimatorContext(targetConfirmationBlocks: max(targetBlocks, 1),
                                                        preference: effectivePreference,
                                                        networkConditions: context.networkConditions)
                if let estimatedRate = estimator(estimatorContext) {
                    return estimatedRate
                }
            }
            
            if let networkConditions = context.networkConditions,
               let networkRate = networkConditions.rate(for: effectivePreference) {
                return networkRate
            }
            
            return determineFallbackRate(for: effectivePreference)
        }
        
        public func update(preference newPreference: Preference? = nil,
                           estimator newEstimator: FeeEstimator? = nil) -> FeePolicy {
            FeePolicy(defaultFeeRate: defaultFeeRate,
                      preference: newPreference ?? preference,
                      estimator: newEstimator ?? estimator)
        }
    }
}

private extension Wallet.FeePolicy {
    func resolveTargetBlocks(preference: Preference,
                             context: RecommendationContext,
                             override: Override?) -> Int? {
        if let overrideTarget = override?.targetConfirmationBlocks, overrideTarget > 0 {
            return overrideTarget
        }
        
        if let contextTarget = context.targetConfirmationBlocks, contextTarget > 0 {
            return contextTarget
        }
        
        return preference.defaultTargetConfirmationBlocks
    }
    
    func determineFallbackRate(for preference: Preference) -> UInt64 {
        switch preference {
        case .economy:
            return defaultFeeRate
        case .standard:
            return multiplySafely(defaultFeeRate, by: 2)
        case .priority:
            return multiplySafely(defaultFeeRate, by: 3)
        }
    }
    
    func multiplySafely(_ value: UInt64, by multiplier: UInt64) -> UInt64 {
        let (product, didOverflow) = value.multipliedReportingOverflow(by: multiplier)
        return didOverflow ? UInt64.max : product
    }
}
