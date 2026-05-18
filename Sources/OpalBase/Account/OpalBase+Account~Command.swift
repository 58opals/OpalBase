// OpalBase+Account~Command.swift

import Foundation
import OpalDiagnostics

// MARK: - UTXO
extension _OpalBase.Account {
    /// Refreshes wallet-owned UTXOs through a public address reader.
    public func refreshUTXOSet(using service: OpalBase.Network.AddressReader, usage: OpalBase.Key.DerivationPath.Usage? = nil) async throws -> UTXORefresh {
        try await OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("utxo_refresh"),
                OpalDiagnostics.Field.module()
            ] + (usage.map { [OpalDiagnostics.Field.usage($0)] } ?? [])
            OpalDiagnostics.record(
                OpalDiagnostics.Event.utxoRefreshStarted,
                category: OpalDiagnostics.Category.addressBook,
                fields: fields
            )
            do {
                let refresh = try await addressBook.refreshUTXOSet(using: service, usage: usage)
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.utxoRefreshSucceeded,
                    category: OpalDiagnostics.Category.addressBook,
                    fields: fields + [
                        OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.addressCount, refresh.utxosByAddress.count),
                        OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.utxoCount, refresh.utxosByAddress.values.reduce(0) { $0 + $1.count })
                    ]
                )
                return UTXORefresh(refresh)
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.utxoRefreshFailed,
                    category: OpalDiagnostics.Category.addressBook,
                    fields: fields + OpalDiagnostics.Field.errorFields(for: error)
                )
                throw error
            }
        }
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
        try await OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("address_reserve"),
                OpalDiagnostics.Field.module(),
                OpalDiagnostics.Field.usage(.receiving)
            ]
            OpalDiagnostics.record(
                OpalDiagnostics.Event.addressReserveStarted,
                category: OpalDiagnostics.Category.addressBook,
                fields: fields
            )
            do {
                let address = try await DerivedAddress(reserveNextReceivingEntry())
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.addressReserveSucceeded,
                    category: OpalDiagnostics.Category.addressBook,
                    fields: fields
                )
                return address
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.addressReserveFailed,
                    category: OpalDiagnostics.Category.addressBook,
                    fields: fields + OpalDiagnostics.Field.errorFields(
                        for: error,
                        fallback: OpalDiagnostics.ErrorCode.addressReservationFailed
                    )
                )
                throw error
            }
        }
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
        try await OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("transaction_history_refresh"),
                OpalDiagnostics.Field.module(),
                OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.includeUnconfirmed, includeUnconfirmed)
            ] + (usage.map { [OpalDiagnostics.Field.usage($0)] } ?? [])
            OpalDiagnostics.record(
                OpalDiagnostics.Event.transactionHistoryRefreshStarted,
                category: OpalDiagnostics.Category.transaction,
                fields: fields
            )
            do {
                let changeSet = try await mapAddressBookError {
                    try await addressBook.refreshTransactionHistory(using: service,
                                                                    usage: usage,
                                                                    includeUnconfirmed: includeUnconfirmed,
                                                                    transactionReader: transactionReader)
                }
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.transactionHistoryRefreshSucceeded,
                    category: OpalDiagnostics.Category.transaction,
                    fields: fields + [
                        OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.transactionCount, changeSet.inserted.count + changeSet.updated.count)
                    ]
                )
                return changeSet
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.transactionHistoryRefreshFailed,
                    category: OpalDiagnostics.Category.transaction,
                    fields: fields + OpalDiagnostics.Field.errorFields(for: error)
                )
                throw error
            }
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
        try await OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("transaction_confirmation_update"),
                OpalDiagnostics.Field.module(),
                OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.transactionCount, transactionHashes.count)
            ]
            OpalDiagnostics.record(
                OpalDiagnostics.Event.transactionConfirmationRefreshStarted,
                category: OpalDiagnostics.Category.transaction,
                fields: fields
            )
            do {
                let changeSet = try await mapAddressBookError {
                    try await addressBook.updateTransactionConfirmations(using: handler,
                                                                         for: transactionHashes)
                }
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.transactionConfirmationRefreshSucceeded,
                    category: OpalDiagnostics.Category.transaction,
                    fields: fields + [
                        OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.confirmationCount, changeSet.updated.count)
                    ]
                )
                return changeSet
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.transactionConfirmationRefreshFailed,
                    category: OpalDiagnostics.Category.transaction,
                    fields: fields + OpalDiagnostics.Field.errorFields(for: error)
                )
                throw error
            }
        }
    }

    func updateTransactionConfirmations(using handler: any OpalBase.Network.TransactionConfirmationClient,
                                        for transactionHashes: [OpalBase.Transaction.Hash]) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await updateTransactionConfirmations(using: .init(confirmations: handler), for: transactionHashes)
    }
    
    public func refreshTransactionConfirmations(using handler: OpalBase.Network.TransactionClient) async throws -> OpalBase.Transaction.History.ChangeSet {
        let records = await addressBook.listTransactionRecords()
        let hashes = records.map(\.transactionHash)
        return try await updateTransactionConfirmations(using: handler, for: hashes)
    }

    func refreshTransactionConfirmations(using handler: any OpalBase.Network.TransactionConfirmationClient) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await refreshTransactionConfirmations(using: .init(confirmations: handler))
    }
}
