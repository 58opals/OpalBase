// Account~TokenInventory.swift

import Foundation

extension Account {
    public func loadUnspentOutputBalances() async throws -> Address.Book.UnspentOutputBalances {
        try await addressBook.calculateUnspentOutputBalances()
    }
    
    public func loadTokenInventory() async throws -> Address.Book.TokenInventory {
        try await addressBook.calculateTokenInventory()
    }
}
