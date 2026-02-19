// Account~Command~ObservationAndRefresh.swift

import Foundation

// MARK: - Monitor
extension Account {
    public func listTrackedEntries() async -> [Address.Book.Entry] {
        await addressBook.listAllEntries()
    }
}

extension Account {
    public func observeNewEntries() async -> AsyncStream<Address.Book.Entry> {
        await addressBook.observeNewEntries()
    }
}

extension Account {
    public func replaceUTXOs(for address: Address,
                             with utxos: [Transaction.Output.Unspent],
                             timestamp: Date = .now) async throws -> Address.Book.UTXOChangeSet {
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

extension Account {
    public func refreshTransactionHistory(for address: Address,
                                          using service: Network.AddressReadable,
                                          includeUnconfirmed: Bool = true,
                                          transactionReader: Network.TransactionReadable? = nil) async throws -> Transaction.History.ChangeSet {
        try await addressBook.refreshTransactionHistory(for: address,
                                                        using: service,
                                                        includeUnconfirmed: includeUnconfirmed,
                                                        transactionReader: transactionReader)
    }
}
