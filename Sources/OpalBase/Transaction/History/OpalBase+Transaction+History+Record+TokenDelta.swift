// OpalBase+Transaction+History+Record+TokenDelta.swift

import Foundation

extension _OpalBase.Transaction.History.Record {
    public struct TokenDelta: Sendable, Hashable, Equatable {
        public var fungibleDeltasByCategory: [OpalBase.CashTokens.CategoryID: Int64]
        /// Non-fungible tokens received by the wallet, preserving multiplicity and transaction order.
        public var nonFungibleTokenAdditions: [OpalBase.CashTokens.TokenData]
        /// Non-fungible tokens spent by the wallet, preserving multiplicity and input order.
        public var nonFungibleTokenRemovals: [OpalBase.CashTokens.TokenData]
        public var bchLockedInTokenOutputDelta: Int64
        
        public init(
            fungibleDeltasByCategory: [OpalBase.CashTokens.CategoryID: Int64] = .init(),
            nonFungibleTokenAdditions: [OpalBase.CashTokens.TokenData] = .init(),
            nonFungibleTokenRemovals: [OpalBase.CashTokens.TokenData] = .init(),
            bchLockedInTokenOutputDelta: Int64 = 0
        ) {
            self.fungibleDeltasByCategory = fungibleDeltasByCategory
            self.nonFungibleTokenAdditions = nonFungibleTokenAdditions
            self.nonFungibleTokenRemovals = nonFungibleTokenRemovals
            self.bchLockedInTokenOutputDelta = bchLockedInTokenOutputDelta
        }
    }
}
