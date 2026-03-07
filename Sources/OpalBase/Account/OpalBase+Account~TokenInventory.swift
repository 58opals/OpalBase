// OpalBase.Account~TokenInventory.swift

import Foundation

extension _OpalBase.Account {
    public func loadUnspentOutputBalances() async throws -> OpalBase.Address.Book.UnspentOutputBalancesModel {
        try await addressBook.calculateUnspentOutputBalances()
    }
    
    public func loadTokenInventory() async throws -> OpalBase.Address.Book.TokenInventoryModel {
        try await addressBook.calculateTokenInventory()
    }
}

