// OpalBase+Account~TokenInventory.swift

import Foundation

extension _OpalBase.Account {
    public func loadUnspentOutputBalances() async throws -> UnspentOutputBalances {
        let balances = try await addressBook.calculateUnspentOutputBalances()
        return UnspentOutputBalances(balances)
    }
    
    public func loadTokenInventory() async throws -> TokenInventory {
        let inventory = try await addressBook.calculateTokenInventory()
        return TokenInventory(inventory)
    }
}
