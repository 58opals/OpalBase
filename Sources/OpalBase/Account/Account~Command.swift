// Account~Command.swift

import Foundation

// MARK: - UTXO
extension Account {
    public func refreshUTXOSet(using service: Network.AddressReadable, usage: DerivationPath.Usage? = nil) async throws -> Address.Book.UTXORefresh {
        try await addressBook.refreshUTXOSet(using: service, usage: usage)
    }
}

// MARK: - Receive
extension Account {
    public func reserveNextReceivingEntry() async throws -> Address.Book.Entry {
        try await addressBook.reserveNextEntry(for: .receiving)
    }
}

// MARK: - Usage
extension Account {
    public func scanForUsedAddresses(using service: Network.AddressReadable,
                                     usage: DerivationPath.Usage? = nil,
                                     includeUnconfirmed: Bool = true) async throws -> Address.Book.UsageScan {
        try await addressBook.scanForUsedAddresses(using: service,
                                                   usage: usage,
                                                   includeUnconfirmed: includeUnconfirmed)
    }
}

// MARK: - History
extension Account {
    public func refreshTransactionHistory(using service: Network.AddressReadable,
                                          usage: DerivationPath.Usage? = nil,
                                          includeUnconfirmed: Bool = true,
                                          transactionReader: Network.TransactionReadable? = nil) async throws -> Transaction.History.ChangeSet {
        try await mapAddressBookError {
            try await addressBook.refreshTransactionHistory(using: service,
                                                            usage: usage,
                                                            includeUnconfirmed: includeUnconfirmed,
                                                            transactionReader: transactionReader)
        }
    }
    
    public func updateTransactionConfirmations(using handler: Network.TransactionConfirmationClient,
                                               for transactionHashes: [Transaction.Hash]) async throws -> Transaction.History.ChangeSet {
        try await mapAddressBookError {
            try await addressBook.updateTransactionConfirmations(using: handler,
                                                                 for: transactionHashes)
        }
    }
    
    public func refreshTransactionConfirmations(using handler: Network.TransactionConfirmationClient) async throws -> Transaction.History.ChangeSet {
        let records = await addressBook.listTransactionRecords()
        let hashes = records.map(\.transactionHash)
        guard !hashes.isEmpty else { return .init() }
        return try await updateTransactionConfirmations(using: handler, for: hashes)
    }
}
