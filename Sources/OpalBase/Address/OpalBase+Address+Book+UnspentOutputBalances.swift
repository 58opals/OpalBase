// OpalBase+Address+Book+UnspentOutputBalances.swift

import Foundation

extension _OpalBase.Address.Book {
    struct UnspentOutputBalances: Sendable, Equatable {
        let bchTotal: OpalBase.Satoshi
        let bchSpendable: OpalBase.Satoshi
        let tokenInventory: TokenInventory
        
        init(bchTotal: OpalBase.Satoshi,
                    bchSpendable: OpalBase.Satoshi,
                    tokenInventory: TokenInventory) {
            self.bchTotal = bchTotal
            self.bchSpendable = bchSpendable
            self.tokenInventory = tokenInventory
        }
    }
}
