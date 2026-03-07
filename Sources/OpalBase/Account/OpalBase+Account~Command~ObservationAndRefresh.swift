// OpalBase+Account~Command~ObservationAndRefresh.swift

import Foundation

// MARK: - MonitorActor
extension _OpalBase.Account {
    public func listTrackedEntries() async -> [OpalBase.Address.Book.EntryModel] {
        await addressBook.listAllEntries()
    }
}

extension _OpalBase.Account {
    public func observeNewEntries() async -> AsyncStream<OpalBase.Address.Book.EntryModel> {
        await addressBook.observeNewEntries()
    }
}

extension _OpalBase.Account {
    public func replaceUTXOs(for address: OpalBase.Address,
                             with utxos: [OpalBase.Transaction.OutputModel.Unspent],
                             timestamp: Date = .now) async throws -> OpalBase.Address.Book.UTXOChangeSetModel {
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

extension _OpalBase.Account {
    public func refreshTransactionHistory(for address: OpalBase.Address,
                                          using service: OpalBase.Network.AddressReadable,
                                          includeUnconfirmed: Bool = true,
                                          transactionReader: OpalBase.Network.TransactionReadableClient? = nil) async throws -> OpalBase.Transaction.HistoryModel.ChangeSet {
        try await addressBook.refreshTransactionHistory(for: address,
                                                        using: service,
                                                        includeUnconfirmed: includeUnconfirmed,
                                                        transactionReader: transactionReader)
    }
}
