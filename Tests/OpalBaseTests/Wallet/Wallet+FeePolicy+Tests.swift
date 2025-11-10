import Foundation
import SwiftFulcrum
import Testing
@testable import OpalBase

@Suite("Wallet Fee Policy", .tags(.wallet))
struct WalletFeePolicyTests {
    @Test("respects explicit fee overrides")
    func testExplicitOverrideWinsOverOtherSources() {
        let policy = Wallet.FeePolicy(defaultFeeRate: 1, preference: .standard) { _ in 2 }
        
        let networkConditions = Wallet.FeePolicy.NetworkConditions(
            recommendedRates: [.standard: 3, .priority: 4],
            fallbackRate: 5
        )
        
        let context = Wallet.FeePolicy.RecommendationContext(
            targetConfirmationBlocks: 24,
            networkConditions: networkConditions
        )
        
        let override = Wallet.FeePolicy.Override(
            explicitFeeRate: 99,
            preference: .economy,
            targetConfirmationBlocks: 2
        )
        
        let recommendation = policy.recommendedFeeRate(for: context, override: override)
        #expect(recommendation == 99)
    }
    
    @Test("falls back to defaults with overflow protection")
    func testFallbackRatesProtectAgainstOverflow() {
        let defaultRate = UInt64.max
        let policy = Wallet.FeePolicy(defaultFeeRate: defaultRate, preference: .economy, estimator: nil)
        
        let baseline = policy.recommendedFeeRate()
        #expect(baseline == defaultRate)
        
        let standardRecommendation = policy.recommendedFeeRate(override: .init(preference: .standard))
        #expect(standardRecommendation == UInt64.max)
        
        let priorityRecommendation = policy.recommendedFeeRate(override: .init(preference: .priority))
        #expect(priorityRecommendation == UInt64.max)
    }
    
    @Test
    func testExplicitOverrideFeeRateIsReturned() {
        let policy = Wallet.FeePolicy(defaultFeeRate: 2)
        let override = Wallet.FeePolicy.Override(explicitFeeRate: 42)
        
        let rate = policy.recommendedFeeRate(override: override)
        
        #expect(rate == 42)
    }
    
    @Test
    func testEstimatorFallsBackToNetworkConditionsWhenNil() {
        let policy = Wallet.FeePolicy(defaultFeeRate: 1, preference: .economy, estimator: nil)
        let networkConditions = Wallet.FeePolicy.NetworkConditions(recommendedRates: [.economy: 55], fallbackRate: 12)
        let context = Wallet.FeePolicy.RecommendationContext(targetConfirmationBlocks: nil, networkConditions: networkConditions)
        
        let rate = policy.recommendedFeeRate(for: context)
        
        #expect(rate == 55)
    }
    
    @Test
    func testFallbackUsesMultipliersForStandardAndPriority() {
        let policy = Wallet.FeePolicy(defaultFeeRate: 10, preference: .economy, estimator: nil)
        let context = Wallet.FeePolicy.RecommendationContext()
        
        let standardOverride = Wallet.FeePolicy.Override(preference: .standard)
        let priorityOverride = Wallet.FeePolicy.Override(preference: .priority)
        
        let standardRate = policy.recommendedFeeRate(for: context, override: standardOverride)
        let priorityRate = policy.recommendedFeeRate(for: context, override: priorityOverride)
        
        #expect(standardRate == 20)
        #expect(priorityRate == 30)
    }
    
    @Test
    func testFallbackRateClampsOnOverflow() {
        let highDefault = UInt64.max / 2 + 1
        let policy = Wallet.FeePolicy(defaultFeeRate: highDefault, preference: .priority, estimator: nil)
        
        let rate = policy.recommendedFeeRate()
        
        #expect(rate == UInt64.max)
    }
    
}
