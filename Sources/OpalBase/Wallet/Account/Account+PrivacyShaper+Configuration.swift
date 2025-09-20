// Account+PrivacyShaper+Configuration.swift

import Foundation

extension Account.PrivacyShaper {
    public struct Configuration: Hashable, Sendable {
        public let batchingIntervalRange: ClosedRange<UInt64>
        public let operationJitterRange: ClosedRange<UInt64>
        
        public let decoyQueryRange: ClosedRange<Int>
        public let decoyProbability: Double
        
        public let randomizeUTXOOrdering: Bool
        public let randomizeRecipientOrdering: Bool
        
        public init(batchingIntervalRange: ClosedRange<UInt64> = 50_000_000 ... 150_000_000,
                    operationJitterRange: ClosedRange<UInt64> = 5_000_000 ... 35_000_000,
                    decoyQueryRange: ClosedRange<Int> = 0 ... 2,
                    decoyProbability: Double = 0.35,
                    randomizeUTXOOrdering: Bool = true,
                    randomizeRecipientOrdering: Bool = true) {
            precondition(batchingIntervalRange.lowerBound <= batchingIntervalRange.upperBound, "Invalid batching interval range")
            precondition(operationJitterRange.lowerBound <= operationJitterRange.upperBound, "Invalid jitter range")
            precondition(decoyQueryRange.lowerBound <= decoyQueryRange.upperBound, "Invalid decoy range")
            precondition((0.0...1.0).contains(decoyProbability), "Decoy probability must be between 0 and 1")
            
            self.batchingIntervalRange = batchingIntervalRange
            self.operationJitterRange = operationJitterRange
            self.decoyQueryRange = decoyQueryRange
            self.decoyProbability = decoyProbability
            self.randomizeUTXOOrdering = randomizeUTXOOrdering
            self.randomizeRecipientOrdering = randomizeRecipientOrdering
        }
        
        public static let standard = Configuration()
    }
}
