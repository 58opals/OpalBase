// OpalBase+Transaction+HistoryModel+RecordModel+TokenDeltaModel.swift

import Foundation

extension _OpalBase.Transaction.HistoryModel.RecordModel {
    public struct TokenDeltaModel: Sendable, Hashable, Equatable {
        public var fungibleDeltasByCategory: [OpalBase.CashTokens.CategoryIDModel: Int64]
        public var nonFungibleTokenAdditions: Set<OpalBase.CashTokens.TokenData>
        public var nonFungibleTokenRemovals: Set<OpalBase.CashTokens.TokenData>
        public var bitcoinCashLockedInTokenOutputDelta: Int64
        
        public init(
            fungibleDeltasByCategory: [OpalBase.CashTokens.CategoryIDModel: Int64] = .init(),
            nonFungibleTokenAdditions: Set<OpalBase.CashTokens.TokenData> = .init(),
            nonFungibleTokenRemovals: Set<OpalBase.CashTokens.TokenData> = .init(),
            bitcoinCashLockedInTokenOutputDelta: Int64 = 0
        ) {
            self.fungibleDeltasByCategory = fungibleDeltasByCategory
            self.nonFungibleTokenAdditions = nonFungibleTokenAdditions
            self.nonFungibleTokenRemovals = nonFungibleTokenRemovals
            self.bitcoinCashLockedInTokenOutputDelta = bitcoinCashLockedInTokenOutputDelta
        }
    }
}

