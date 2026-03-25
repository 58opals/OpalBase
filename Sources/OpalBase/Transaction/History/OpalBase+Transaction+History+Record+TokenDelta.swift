// OpalBase+Transaction+History+Record+TokenDelta.swift

import Foundation

extension _OpalBase.Transaction.History.Record {
    public struct TokenDelta: Sendable, Hashable, Equatable {
        public var fungibleDeltasByCategory: [OpalBase.CashTokens.CategoryID: Int64]
        public var nonFungibleTokenAdditions: Set<OpalBase.CashTokens.TokenData>
        public var nonFungibleTokenRemovals: Set<OpalBase.CashTokens.TokenData>
        public var bchLockedInTokenOutputDelta: Int64
        
        public init(
            fungibleDeltasByCategory: [OpalBase.CashTokens.CategoryID: Int64] = .init(),
            nonFungibleTokenAdditions: Set<OpalBase.CashTokens.TokenData> = .init(),
            nonFungibleTokenRemovals: Set<OpalBase.CashTokens.TokenData> = .init(),
            bchLockedInTokenOutputDelta: Int64 = 0
        ) {
            self.fungibleDeltasByCategory = fungibleDeltasByCategory
            self.nonFungibleTokenAdditions = nonFungibleTokenAdditions
            self.nonFungibleTokenRemovals = nonFungibleTokenRemovals
            self.bchLockedInTokenOutputDelta = bchLockedInTokenOutputDelta
        }
    }
}

