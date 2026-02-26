// AccountActor~Convenience.swift

import Foundation

extension AccountActor {
    public func reserveNextReceivingAddress() async throws -> AddressModel {
        let entry = try await reserveNextReceivingEntry()
        return entry.address
    }
    
    public func reserveNextReceivingAddressString() async throws -> String {
        let address = try await reserveNextReceivingAddress()
        return address.string
    }
}

extension AccountActor {
    public func calculateTotalBalance() async throws -> SatoshiModel {
        try await addressBook.calculateTotalUnspentBalance()
    }
}

extension AccountActor {
    public func listTransactions() async -> [TransactionModel.HistoryModel.RecordModel] {
        await addressBook.listTransactionRecords()
    }
}

extension AccountActor {
    public func refreshTransactionHistoryAndList(using service: NetworkModel.AddressReadable,
                                                 usage: DerivationPathModel.UsageModel? = nil,
                                                 includeUnconfirmed: Bool = true) async throws -> [TransactionModel.HistoryModel.RecordModel] {
        _ = try await refreshTransactionHistory(using: service,
                                                usage: usage,
                                                includeUnconfirmed: includeUnconfirmed)
        return await listTransactions()
    }
    
    public func refreshTransactionConfirmationsAndList(using handler: NetworkModel.TransactionConfirmationClient) async throws -> [TransactionModel.HistoryModel.RecordModel] {
        _ = try await refreshTransactionConfirmations(using: handler)
        return await listTransactions()
    }
}
