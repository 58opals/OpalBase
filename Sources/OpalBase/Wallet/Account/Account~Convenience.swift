// Account~Convenience.swift

import Foundation

extension Account {
    public func reserveNextReceivingAddress() async throws -> Address {
        let entry = try await reserveNextReceivingEntry()
        return entry.address
    }
    
    public func reserveNextReceivingAddressString() async throws -> String {
        let address = try await reserveNextReceivingAddress()
        return address.string
    }
}

extension Account {
    public func calculateTotalBalance() async -> Satoshi {
        await addressBook.calculateTotalUnspentBalance()
    }
}

extension Account {
    public func listTransactions() async -> [Transaction.History.Record] {
        await addressBook.listTransactionRecords()
    }
}

extension Account {
    public func refreshTransactionHistoryAndList(using service: Network.AddressReadable,
                                                 usage: DerivationPath.Usage? = nil,
                                                 includeUnconfirmed: Bool = true) async throws -> [Transaction.History.Record] {
        _ = try await refreshTransactionHistory(using: service,
                                                usage: usage,
                                                includeUnconfirmed: includeUnconfirmed)
        return await listTransactions()
    }
    
    public func refreshTransactionConfirmationsAndList(using handler: Network.TransactionConfirming) async throws -> [Transaction.History.Record] {
        _ = try await refreshTransactionConfirmations(using: handler)
        return await listTransactions()
    }
}
