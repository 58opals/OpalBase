// OpalBase+Account~Convenience.swift

import Foundation

extension _OpalBase.Account {
    public func reserveNextReceivingAddress() async throws -> OpalBase.Address {
        let entry = try await reserveNextReceivingEntry()
        return entry.address
    }
    
    public func reserveNextReceivingAddressString() async throws -> String {
        let address = try await reserveNextReceivingAddress()
        return address.string
    }
}

extension _OpalBase.Account {
    public func calculateTotalBalance() async throws -> OpalBase.Satoshi {
        try await addressBook.calculateTotalUnspentBalance()
    }
}

extension _OpalBase.Account {
    public func listTransactions() async -> [OpalBase.Transaction.HistoryModel.RecordModel] {
        await addressBook.listTransactionRecords()
    }
}

extension _OpalBase.Account {
    public func refreshTransactionHistoryAndList(using service: OpalBase.Network.AddressReadable,
                                                 usage: OpalBase.DerivationPath.UsageModel? = nil,
                                                 includeUnconfirmed: Bool = true) async throws -> [OpalBase.Transaction.HistoryModel.RecordModel] {
        _ = try await refreshTransactionHistory(using: service,
                                                usage: usage,
                                                includeUnconfirmed: includeUnconfirmed)
        return await listTransactions()
    }
    
    public func refreshTransactionConfirmationsAndList(using handler: OpalBase.Network.TransactionConfirmationClient) async throws -> [OpalBase.Transaction.HistoryModel.RecordModel] {
        _ = try await refreshTransactionConfirmations(using: handler)
        return await listTransactions()
    }
}
