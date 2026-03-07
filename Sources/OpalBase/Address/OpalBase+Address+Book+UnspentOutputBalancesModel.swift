// OpalBase+Address+Book+UnspentOutputBalancesModel.swift

import Foundation

extension _OpalBase.Address.Book {
    public struct UnspentOutputBalancesModel: Sendable, Equatable {
        public let bchTotal: OpalBase.Satoshi
        public let bchSpendable: OpalBase.Satoshi
        public let tokenInventory: TokenInventoryModel
        
        public init(bchTotal: OpalBase.Satoshi,
                    bchSpendable: OpalBase.Satoshi,
                    tokenInventory: TokenInventoryModel) {
            self.bchTotal = bchTotal
            self.bchSpendable = bchSpendable
            self.tokenInventory = tokenInventory
        }
    }
}
