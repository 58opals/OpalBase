import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Wallet Fee Policy", .tags(.wallet))
struct WalletFeePolicyTests {
    private static let healthyServerAddress = URL(string: "wss://bch.imaginary.cash:50004")!
    
    @Test("recommended fee rate returns explicit override before other inputs")
    func testRecommendFeeRateRespectsExplicitOverride() {
        let policy = Wallet.FeePolicy(defaultFeeRate: 12,
                                      preference: .economy)
        let networkConditions = Wallet.FeePolicy.NetworkConditions(recommendedRates: [.economy: 48,
                                                                                      .priority: 96],
                                                                   fallbackRate: 24)
        let context = Wallet.FeePolicy.RecommendationContext(targetConfirmationBlocks: 4,
                                                             networkConditions: networkConditions)
        let override = Wallet.FeePolicy.Override(explicitFeeRate: 144,
                                                 preference: .priority,
                                                 targetConfirmationBlocks: 2)
        
        let recommended = policy.recommendedFeeRate(for: context, override: override)
        
        #expect(recommended == 144)
    }
    
    @Test("recommended fee rate leverages network conditions and preference updates")
    func testRecommendFeeRateUsesNetworkConditions() {
        let networkConditions = Wallet.FeePolicy.NetworkConditions(recommendedRates: [.economy: 4,
                                                                                      .standard: 8],
                                                                   fallbackRate: 12)
        let context = Wallet.FeePolicy.RecommendationContext(networkConditions: networkConditions)
        
        let economyPolicy = Wallet.FeePolicy(defaultFeeRate: 2,
                                             preference: .economy,
                                             estimator: nil)
        #expect(economyPolicy.recommendedFeeRate(for: context) == 4)
        
        let standardPolicy = economyPolicy.updating(preference: .standard)
        #expect(standardPolicy.recommendedFeeRate(for: context) == 8)
        
        let priorityPolicy = standardPolicy.updating(preference: .priority)
        #expect(priorityPolicy.recommendedFeeRate(for: context) == 12)
    }
    
    @Test("fallback fee rate protects against multiplication overflow")
    func testFallbackRateSaturatesOnOverflow() {
        let maximumPolicy = Wallet.FeePolicy(defaultFeeRate: UInt64.max,
                                             preference: .standard)
        #expect(maximumPolicy.recommendedFeeRate() == UInt64.max)
        
        let nearOverflowPolicy = Wallet.FeePolicy(defaultFeeRate: (UInt64.max / 2) + 1,
                                                  preference: .priority)
        #expect(nearOverflowPolicy.recommendedFeeRate() == UInt64.max)
        
        let economyPolicy = Wallet.FeePolicy(defaultFeeRate: UInt64.max,
                                             preference: .economy)
        #expect(economyPolicy.recommendedFeeRate() == UInt64.max)
    }
}
