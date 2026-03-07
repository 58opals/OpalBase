// TransactionModel+HistoryModel+RecordModel+TokenDeltaModel.swift

import Foundation

extension TransactionModel.HistoryModel.RecordModel {
    public struct TokenDeltaModel: Sendable, Hashable, Equatable {
        public var fungibleDeltasByCategory: [CashTokensModel.CategoryIDModel: Int64]
        public var nonFungibleTokenAdditions: Set<CashTokensModel.TokenData>
        public var nonFungibleTokenRemovals: Set<CashTokensModel.TokenData>
        public var bitcoinCashLockedInTokenOutputDelta: Int64
        
        public init(
            fungibleDeltasByCategory: [CashTokensModel.CategoryIDModel: Int64] = .init(),
            nonFungibleTokenAdditions: Set<CashTokensModel.TokenData> = .init(),
            nonFungibleTokenRemovals: Set<CashTokensModel.TokenData> = .init(),
            bitcoinCashLockedInTokenOutputDelta: Int64 = 0
        ) {
            self.fungibleDeltasByCategory = fungibleDeltasByCategory
            self.nonFungibleTokenAdditions = nonFungibleTokenAdditions
            self.nonFungibleTokenRemovals = nonFungibleTokenRemovals
            self.bitcoinCashLockedInTokenOutputDelta = bitcoinCashLockedInTokenOutputDelta
        }
    }
}

