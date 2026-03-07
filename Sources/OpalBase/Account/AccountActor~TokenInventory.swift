// AccountActor~TokenInventory.swift

import Foundation

extension AccountActor {
    public func loadUnspentOutputBalances() async throws -> AddressModel.BookActor.UnspentOutputBalancesModel {
        try await addressBook.calculateUnspentOutputBalances()
    }
    
    public func loadTokenInventory() async throws -> AddressModel.BookActor.TokenInventoryModel {
        try await addressBook.calculateTokenInventory()
    }
}

