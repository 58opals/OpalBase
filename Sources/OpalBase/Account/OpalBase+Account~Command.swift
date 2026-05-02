// OpalBase+Account~Command.swift

import Foundation

// MARK: - UTXO
extension _OpalBase.Account {
    /// Refreshes wallet-owned UTXOs through a public address reader.
    public func refreshUTXOSet(using service: OpalBase.Network.AddressReader, usage: OpalBase.Key.DerivationPath.Usage? = nil) async throws -> UTXORefresh {
        let refresh = try await addressBook.refreshUTXOSet(using: service, usage: usage)
        return UTXORefresh(refresh)
    }

    func refreshAddressBookUTXOSet(using service: any OpalBase.Network.AddressReadable,
                                   usage: OpalBase.Key.DerivationPath.Usage? = nil) async throws -> OpalBase.Address.Book.UTXORefresh {
        try await addressBook.refreshUTXOSet(using: service, usage: usage)
    }
}

// MARK: - Receive
extension _OpalBase.Account {
    /// Reserves the next receiving address for handing out to a payer.
    public func reserveNextReceivingDerivedAddress() async throws -> DerivedAddress {
        try await DerivedAddress(reserveNextReceivingEntry())
    }

    func reserveNextReceivingEntry() async throws -> OpalBase.Address.Book.Entry {
        try await addressBook.reserveNextEntry(for: .receiving)
    }
}

// MARK: - Usage
extension _OpalBase.Account {
    func scanForUsedAddresses(using service: OpalBase.Network.AddressReader,
                              usage: OpalBase.Key.DerivationPath.Usage? = nil,
                              includeUnconfirmed: Bool = true) async throws -> OpalBase.Address.Book.UsageScan {
        try await addressBook.scanForUsedAddresses(using: service,
                                                   usage: usage,
                                                   includeUnconfirmed: includeUnconfirmed)
    }

    func scanForUsedAddresses(using service: any OpalBase.Network.AddressReadable,
                              usage: OpalBase.Key.DerivationPath.Usage? = nil,
                              includeUnconfirmed: Bool = true) async throws -> OpalBase.Address.Book.UsageScan {
        try await scanForUsedAddresses(using: .init(service),
                                       usage: usage,
                                       includeUnconfirmed: includeUnconfirmed)
    }
}

// MARK: - History
extension _OpalBase.Account {
    public func refreshTransactionHistory(using service: OpalBase.Network.AddressReader,
                                          usage: OpalBase.Key.DerivationPath.Usage? = nil,
                                          includeUnconfirmed: Bool = true,
                                          transactionReader: OpalBase.Network.TransactionReader? = nil) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await mapAddressBookError {
            try await addressBook.refreshTransactionHistory(using: service,
                                                            usage: usage,
                                                            includeUnconfirmed: includeUnconfirmed,
                                                            transactionReader: transactionReader)
        }
    }

    func refreshTransactionHistory(using service: any OpalBase.Network.AddressReadable,
                                   usage: OpalBase.Key.DerivationPath.Usage? = nil,
                                   includeUnconfirmed: Bool = true,
                                   transactionReader: (any OpalBase.Network.TransactionReadableClient)? = nil) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await refreshTransactionHistory(using: .init(service),
                                            usage: usage,
                                            includeUnconfirmed: includeUnconfirmed,
                                            transactionReader: transactionReader.map(OpalBase.Network.TransactionReader.init(_:)))
    }
    
    public func updateTransactionConfirmations(using handler: OpalBase.Network.TransactionClient,
                                               for transactionHashes: [OpalBase.Transaction.Hash]) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await mapAddressBookError {
            try await addressBook.updateTransactionConfirmations(using: handler,
                                                                 for: transactionHashes)
        }
    }

    func updateTransactionConfirmations(using handler: any OpalBase.Network.TransactionConfirmationClient,
                                        for transactionHashes: [OpalBase.Transaction.Hash]) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await updateTransactionConfirmations(using: .init(confirmations: handler), for: transactionHashes)
    }
    
    public func refreshTransactionConfirmations(using handler: OpalBase.Network.TransactionClient) async throws -> OpalBase.Transaction.History.ChangeSet {
        let records = await addressBook.listTransactionRecords()
        let hashes = records.map(\.transactionHash)
        guard !hashes.isEmpty else { return .init() }
        return try await updateTransactionConfirmations(using: handler, for: hashes)
    }

    func refreshTransactionConfirmations(using handler: any OpalBase.Network.TransactionConfirmationClient) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await refreshTransactionConfirmations(using: .init(confirmations: handler))
    }
}
