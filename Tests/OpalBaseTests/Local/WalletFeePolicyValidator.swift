import Foundation
import Testing
@testable import OpalBase

@Suite("WalletActor Fee Policy", .tags(.wallet))
struct WalletFeePolicyValidator {
    @Test("respects explicit fee overrides")
    func explicitOverrideWinsOverOtherSources() {
        let policy = WalletActor.FeePolicy(defaultFeeRate: 1, preference: .standard) { _ in 2 }
        
        let networkConditions = WalletActor.FeePolicy.NetworkConditions(
            recommendedRates: [.standard: 3, .priority: 4],
            fallbackRate: 5
        )
        
        let context = WalletActor.FeePolicy.RecommendationContext(
            targetConfirmationBlocks: 24,
            networkConditions: networkConditions
        )
        
        let override = WalletActor.FeePolicy.Override(
            explicitFeeRate: 99,
            preference: .economy,
            targetConfirmationBlocks: 2
        )
        
        let recommendation = policy.recommendFeeRate(for: context, override: override)
        #expect(recommendation == 99)
    }
    
    @Test("falls back to defaults with overflow protection")
    func fallbackRatesProtectAgainstOverflow() {
        let defaultRate = UInt64.max
        let policy = WalletActor.FeePolicy(defaultFeeRate: defaultRate, preference: .economy, estimator: nil)
        
        let baseline = policy.recommendFeeRate()
        #expect(baseline == defaultRate)
        
        let standardRecommendation = policy.recommendFeeRate(override: .init(preference: .standard))
        #expect(standardRecommendation == UInt64.max)
        
        let priorityRecommendation = policy.recommendFeeRate(override: .init(preference: .priority))
        #expect(priorityRecommendation == UInt64.max)
    }
    
    @Test("returns explicit override fee rate")
    func explicitOverrideFeeRateIsReturned() {
        let policy = WalletActor.FeePolicy(defaultFeeRate: 2)
        let override = WalletActor.FeePolicy.Override(explicitFeeRate: 42)
        
        let rate = policy.recommendFeeRate(override: override)
        
        #expect(rate == 42)
    }
    
    @Test("falls back to network conditions when estimator is nil")
    func estimatorFallsBackToNetworkConditionsWhenNil() {
        let policy = WalletActor.FeePolicy(defaultFeeRate: 1, preference: .economy, estimator: nil)
        let networkConditions = WalletActor.FeePolicy.NetworkConditions(recommendedRates: [.economy: 55], fallbackRate: 12)
        let context = WalletActor.FeePolicy.RecommendationContext(targetConfirmationBlocks: nil, networkConditions: networkConditions)
        
        let rate = policy.recommendFeeRate(for: context)
        
        #expect(rate == 55)
    }
    
    @Test("uses standard and priority multipliers for fallback rates")
    func fallbackUsesMultipliersForStandardAndPriority() {
        let policy = WalletActor.FeePolicy(defaultFeeRate: 10, preference: .economy, estimator: nil)
        let context = WalletActor.FeePolicy.RecommendationContext()
        
        let standardOverride = WalletActor.FeePolicy.Override(preference: .standard)
        let priorityOverride = WalletActor.FeePolicy.Override(preference: .priority)
        
        let standardRate = policy.recommendFeeRate(for: context, override: standardOverride)
        let priorityRate = policy.recommendFeeRate(for: context, override: priorityOverride)
        
        #expect(standardRate == 20)
        #expect(priorityRate == 30)
    }
    
    @Test("clamps fallback rate on overflow")
    func fallbackRateClampsOnOverflow() {
        let highDefault = UInt64.max / 2 + 1
        let policy = WalletActor.FeePolicy(defaultFeeRate: highDefault, preference: .priority, estimator: nil)
        
        let rate = policy.recommendFeeRate()
        
        #expect(rate == UInt64.max)
    }
    
}
