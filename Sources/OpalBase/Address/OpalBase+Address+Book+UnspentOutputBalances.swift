// OpalBase+Address+Book+UnspentOutputBalances.swift

import Foundation

extension _OpalBase.Address.Book {
    public struct UnspentOutputBalances: Sendable, Equatable {
        public let bchTotal: OpalBase.Satoshi
        public let bchSpendable: OpalBase.Satoshi
        public let tokenInventory: TokenInventory
        
        public init(bchTotal: OpalBase.Satoshi,
                    bchSpendable: OpalBase.Satoshi,
                    tokenInventory: TokenInventory) {
            self.bchTotal = bchTotal
            self.bchSpendable = bchSpendable
            self.tokenInventory = tokenInventory
        }
    }
}
