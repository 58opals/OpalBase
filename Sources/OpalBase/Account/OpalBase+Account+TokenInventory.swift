// OpalBase+Account+TokenInventory.swift

import Foundation

extension _OpalBase.Account {
    struct TokenInventory {
        let category: OpalBase.CashTokens.CategoryID
        let fungibleAmount: UInt64
        let nonFungibleTokens: [OpalBase.Address.Book.TokenInventory.NonFungibleTokenGroup: Int]
    }
}
