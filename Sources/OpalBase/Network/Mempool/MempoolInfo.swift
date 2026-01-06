// Network+MempoolInfo.swift

import Foundation

extension Network {
    public struct MempoolInfo: Sendable, Equatable {
        public let mempoolMinimumFee: Double?
        public let minimumRelayTransactionFee: Double?
        public let incrementalRelayFee: Double?
        public let unbroadcastCount: Int?
        public let isFullReplaceByFeeEnabled: Bool?
        
        public init(
            mempoolMinimumFee: Double?,
            minimumRelayTransactionFee: Double?,
            incrementalRelayFee: Double?,
            unbroadcastCount: Int?,
            isFullReplaceByFeeEnabled: Bool?
        ) {
            self.mempoolMinimumFee = mempoolMinimumFee
            self.minimumRelayTransactionFee = minimumRelayTransactionFee
            self.incrementalRelayFee = incrementalRelayFee
            self.unbroadcastCount = unbroadcastCount
            self.isFullReplaceByFeeEnabled = isFullReplaceByFeeEnabled
        }
    }
}
