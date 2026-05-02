// OpalBase+Account~Command~ObservationAndRefresh.swift

import Foundation

// MARK: - Address Book Observation And Refresh
extension _OpalBase.Account {
    func listTrackedEntries() async -> [OpalBase.Address.Book.Entry] {
        await addressBook.listAllEntries()
    }
}

extension _OpalBase.Account {
    func observeNewEntries() async -> AsyncStream<OpalBase.Address.Book.Entry> {
        await addressBook.observeNewEntries()
    }
}

extension _OpalBase.Account {
    func replaceUTXOs(for address: OpalBase.Address,
                      with utxos: [OpalBase.Transaction.Output.Unspent],
                      timestamp: Date = .now) async throws -> UTXOChangeSet {
        let changeSet = try await addressBook.replaceUTXOs(for: address,
                                                           with: utxos,
                                                           timestamp: timestamp)
        
        if !changeSet.updated.isEmpty {
            try await addressBook.mark(address: address, isUsed: true)
        }
        
        try await addressBook.updateCachedBalance(for: address,
                                                  balance: changeSet.balance,
                                                  timestamp: timestamp)
        return UTXOChangeSet(changeSet)
    }
}

extension _OpalBase.Account {
    func refreshTransactionHistory(for address: OpalBase.Address,
                                   using service: OpalBase.Network.AddressReader,
                                   includeUnconfirmed: Bool = true,
                                   transactionReader: OpalBase.Network.TransactionReader? = nil) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await addressBook.refreshTransactionHistory(for: address,
                                                        using: service,
                                                        includeUnconfirmed: includeUnconfirmed,
                                                        transactionReader: transactionReader)
    }

    func refreshTransactionHistory(for address: OpalBase.Address,
                                   using service: any OpalBase.Network.AddressReadable,
                                   includeUnconfirmed: Bool = true,
                                   transactionReader: (any OpalBase.Network.TransactionReadableClient)? = nil) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await refreshTransactionHistory(for: address,
                                            using: .init(service),
                                            includeUnconfirmed: includeUnconfirmed,
                                            transactionReader: transactionReader.map(OpalBase.Network.TransactionReader.init(_:)))
    }
}
