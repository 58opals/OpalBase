// OpalBase+Account~Command.swift

import Foundation

// MARK: - UTXOModel
extension _OpalBase.Account {
    public func refreshUTXOSet(using service: OpalBase.Network.AddressReadable, usage: OpalBase.DerivationPath.UsageModel? = nil) async throws -> OpalBase.Address.Book.UTXORefreshModel {
        try await addressBook.refreshUTXOSet(using: service, usage: usage)
    }
}

// MARK: - Receive
extension _OpalBase.Account {
    public func reserveNextReceivingEntry() async throws -> OpalBase.Address.Book.EntryModel {
        try await addressBook.reserveNextEntry(for: .receiving)
    }
}

// MARK: - UsageModel
extension _OpalBase.Account {
    public func scanForUsedAddresses(using service: OpalBase.Network.AddressReadable,
                                     usage: OpalBase.DerivationPath.UsageModel? = nil,
                                     includeUnconfirmed: Bool = true) async throws -> OpalBase.Address.Book.UsageScanModel {
        try await addressBook.scanForUsedAddresses(using: service,
                                                   usage: usage,
                                                   includeUnconfirmed: includeUnconfirmed)
    }
}

// MARK: - HistoryModel
extension _OpalBase.Account {
    public func refreshTransactionHistory(using service: OpalBase.Network.AddressReadable,
                                          usage: OpalBase.DerivationPath.UsageModel? = nil,
                                          includeUnconfirmed: Bool = true,
                                          transactionReader: OpalBase.Network.TransactionReadableClient? = nil) async throws -> OpalBase.Transaction.HistoryModel.ChangeSetModel {
        try await mapAddressBookError {
            try await addressBook.refreshTransactionHistory(using: service,
                                                            usage: usage,
                                                            includeUnconfirmed: includeUnconfirmed,
                                                            transactionReader: transactionReader)
        }
    }
    
    public func updateTransactionConfirmations(using handler: OpalBase.Network.TransactionConfirmationClient,
                                               for transactionHashes: [OpalBase.Transaction.HashModel]) async throws -> OpalBase.Transaction.HistoryModel.ChangeSetModel {
        try await mapAddressBookError {
            try await addressBook.updateTransactionConfirmations(using: handler,
                                                                 for: transactionHashes)
        }
    }
    
    public func refreshTransactionConfirmations(using handler: OpalBase.Network.TransactionConfirmationClient) async throws -> OpalBase.Transaction.HistoryModel.ChangeSetModel {
        let records = await addressBook.listTransactionRecords()
        let hashes = records.map(\.transactionHash)
        guard !hashes.isEmpty else { return .init() }
        return try await updateTransactionConfirmations(using: handler, for: hashes)
    }
}
