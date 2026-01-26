// Transaction+History+TokenDelta.swift

import Foundation

extension Transaction.History.Record {
    public struct TokenDelta: Sendable, Hashable, Equatable {
        public var fungibleDeltasByCategory: [CashTokens.CategoryID: Int64]
        public var nonFungibleTokenAdditions: Set<CashTokens.TokenData>
        public var nonFungibleTokenRemovals: Set<CashTokens.TokenData>
        public var bitcoinCashLockedInTokenOutputDelta: Int64
        
        public init(
            fungibleDeltasByCategory: [CashTokens.CategoryID: Int64] = .init(),
            nonFungibleTokenAdditions: Set<CashTokens.TokenData> = .init(),
            nonFungibleTokenRemovals: Set<CashTokens.TokenData> = .init(),
            bitcoinCashLockedInTokenOutputDelta: Int64 = 0
        ) {
            self.fungibleDeltasByCategory = fungibleDeltasByCategory
            self.nonFungibleTokenAdditions = nonFungibleTokenAdditions
            self.nonFungibleTokenRemovals = nonFungibleTokenRemovals
            self.bitcoinCashLockedInTokenOutputDelta = bitcoinCashLockedInTokenOutputDelta
        }
    }
}
