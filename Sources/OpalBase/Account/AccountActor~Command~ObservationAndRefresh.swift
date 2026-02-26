// AccountActor~Command~ObservationAndRefresh.swift

import Foundation

// MARK: - MonitorActor
extension AccountActor {
    public func listTrackedEntries() async -> [AddressModel.BookActor.EntryModel] {
        await addressBook.listAllEntries()
    }
}

extension AccountActor {
    public func observeNewEntries() async -> AsyncStream<AddressModel.BookActor.EntryModel> {
        await addressBook.observeNewEntries()
    }
}

extension AccountActor {
    public func replaceUTXOs(for address: AddressModel,
                             with utxos: [TransactionModel.OutputModel.UnspentModel],
                             timestamp: Date = .now) async throws -> AddressModel.BookActor.UTXOChangeSetModel {
        let changeSet = try await addressBook.replaceUTXOs(for: address,
                                                           with: utxos,
                                                           timestamp: timestamp)
        
        if !changeSet.updated.isEmpty {
            try await addressBook.mark(address: address, isUsed: true)
        }
        
        try await addressBook.updateCachedBalance(for: address,
                                                  balance: changeSet.balance,
                                                  timestamp: timestamp)
        return changeSet
    }
}

extension AccountActor {
    public func refreshTransactionHistory(for address: AddressModel,
                                          using service: NetworkModel.AddressReadable,
                                          includeUnconfirmed: Bool = true,
                                          transactionReader: NetworkModel.TransactionReadableClient? = nil) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
        try await addressBook.refreshTransactionHistory(for: address,
                                                        using: service,
                                                        includeUnconfirmed: includeUnconfirmed,
                                                        transactionReader: transactionReader)
    }
}
