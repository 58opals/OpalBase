// OpalBase+Account+PrivacyShaperActor+Configuration.swift

import Foundation

extension _OpalBase.Account.PrivacyShaperActor {
    struct Configuration: Hashable, Sendable {
        let batchingIntervalRange: ClosedRange<UInt64>
        let operationJitterRange: ClosedRange<UInt64>
        
        let decoyQueryRange: ClosedRange<Int>
        let decoyProbability: Double
        
        let shouldRandomizeUTXOOrdering: Bool
        let shouldRandomizeRecipientOrdering: Bool
        
        init(batchingIntervalRange: ClosedRange<UInt64> = 50_000_000 ... 150_000_000,
             operationJitterRange: ClosedRange<UInt64> = 5_000_000 ... 35_000_000,
             decoyQueryRange: ClosedRange<Int> = 0 ... 2,
             decoyProbability: Double = 0.35,
             shouldRandomizeUTXOOrdering: Bool = true,
             shouldRandomizeRecipientOrdering: Bool = true) {
            precondition(batchingIntervalRange.lowerBound <= batchingIntervalRange.upperBound, "Invalid batching interval range")
            precondition(operationJitterRange.lowerBound <= operationJitterRange.upperBound, "Invalid jitter range")
            precondition(decoyQueryRange.lowerBound <= decoyQueryRange.upperBound, "Invalid decoy range")
            precondition((0.0...1.0).contains(decoyProbability), "Decoy probability must be between 0 and 1")
            
            self.batchingIntervalRange = batchingIntervalRange
            self.operationJitterRange = operationJitterRange
            self.decoyQueryRange = decoyQueryRange
            self.decoyProbability = decoyProbability
            self.shouldRandomizeUTXOOrdering = shouldRandomizeUTXOOrdering
            self.shouldRandomizeRecipientOrdering = shouldRandomizeRecipientOrdering
        }
        
        static let standard = Configuration()
    }
}
