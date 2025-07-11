// Wallet+Network+FeeRate.swift

import Foundation

extension Wallet.Network {
    public actor FeeRate {
        private let fulcrumPool: Wallet.Network.FulcrumPool
        
        public init(fulcrumPool: Wallet.Network.FulcrumPool) {
            self.fulcrumPool = fulcrumPool
        }
        
        public func getRecommendedFeeRate() async throws -> UInt64 {
            let fulcrum = try await fulcrumPool.getFulcrum()
            let estimateFee = try await Transaction.estimateFee(numberOfBlocks: 1, using: fulcrum)
            let relayFee = try await Transaction.relayFee(using: fulcrum)
            
            return max(estimateFee.uint64, relayFee.uint64)
        }
    }
}
