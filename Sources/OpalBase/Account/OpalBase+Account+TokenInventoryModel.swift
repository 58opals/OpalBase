// OpalBase+Account+TokenInventoryModel.swift

import Foundation

extension _OpalBase.Account {
    struct TokenInventoryModel {
        let category: OpalBase.CashTokens.CategoryIDModel
        let fungibleAmount: UInt64
        let nonFungibleTokens: [OpalBase.Address.Book.TokenInventoryModel.NonFungibleTokenGroup: Int]
    }
}
