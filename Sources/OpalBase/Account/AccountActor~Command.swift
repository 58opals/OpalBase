// AccountActor~Command.swift

import Foundation

// MARK: - UTXOModel
extension AccountActor {
    public func refreshUTXOSet(using service: NetworkModel.AddressReadable, usage: DerivationPathModel.UsageModel? = nil) async throws -> AddressModel.BookActor.UTXORefreshModel {
        try await addressBook.refreshUTXOSet(using: service, usage: usage)
    }
}

// MARK: - Receive
extension AccountActor {
    public func reserveNextReceivingEntry() async throws -> AddressModel.BookActor.EntryModel {
        try await addressBook.reserveNextEntry(for: .receiving)
    }
}

// MARK: - UsageModel
extension AccountActor {
    public func scanForUsedAddresses(using service: NetworkModel.AddressReadable,
                                     usage: DerivationPathModel.UsageModel? = nil,
                                     includeUnconfirmed: Bool = true) async throws -> AddressModel.BookActor.UsageScanModel {
        try await addressBook.scanForUsedAddresses(using: service,
                                                   usage: usage,
                                                   includeUnconfirmed: includeUnconfirmed)
    }
}

// MARK: - HistoryModel
extension AccountActor {
    public func refreshTransactionHistory(using service: NetworkModel.AddressReadable,
                                          usage: DerivationPathModel.UsageModel? = nil,
                                          includeUnconfirmed: Bool = true,
                                          transactionReader: NetworkModel.TransactionReadableClient? = nil) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
        try await mapAddressBookError {
            try await addressBook.refreshTransactionHistory(using: service,
                                                            usage: usage,
                                                            includeUnconfirmed: includeUnconfirmed,
                                                            transactionReader: transactionReader)
        }
    }
    
    public func updateTransactionConfirmations(using handler: NetworkModel.TransactionConfirmationClient,
                                               for transactionHashes: [TransactionModel.HashModel]) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
        try await mapAddressBookError {
            try await addressBook.updateTransactionConfirmations(using: handler,
                                                                 for: transactionHashes)
        }
    }
    
    public func refreshTransactionConfirmations(using handler: NetworkModel.TransactionConfirmationClient) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
        let records = await addressBook.listTransactionRecords()
        let hashes = records.map(\.transactionHash)
        guard !hashes.isEmpty else { return .init() }
        return try await updateTransactionConfirmations(using: handler, for: hashes)
    }
}
