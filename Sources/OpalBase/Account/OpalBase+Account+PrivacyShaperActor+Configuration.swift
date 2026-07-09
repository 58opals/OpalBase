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
            self.batchingIntervalRange = Self.positiveNanosecondRange(batchingIntervalRange)
            self.operationJitterRange = Self.positiveNanosecondRange(operationJitterRange)
            self.decoyQueryRange = Self.nonNegativeDecoyQueryRange(decoyQueryRange)
            self.decoyProbability = Self.clampedDecoyProbability(decoyProbability)
            self.shouldRandomizeUTXOOrdering = shouldRandomizeUTXOOrdering
            self.shouldRandomizeRecipientOrdering = shouldRandomizeRecipientOrdering
        }
        
        static let standard = Configuration()

        private static func clampedDecoyProbability(_ decoyProbability: Double) -> Double {
            guard !decoyProbability.isNaN else { return 0 }
            return min(max(decoyProbability, 0), 1)
        }

        private static func nonNegativeDecoyQueryRange(_ decoyQueryRange: ClosedRange<Int>) -> ClosedRange<Int> {
            let lowerBound = max(0, decoyQueryRange.lowerBound)
            let upperBound = max(lowerBound, decoyQueryRange.upperBound)
            return lowerBound ... upperBound
        }

        private static func positiveNanosecondRange(_ range: ClosedRange<UInt64>) -> ClosedRange<UInt64> {
            let lowerBound = max(1, range.lowerBound)
            let upperBound = max(lowerBound, range.upperBound)
            return lowerBound ... upperBound
        }

    }
}
