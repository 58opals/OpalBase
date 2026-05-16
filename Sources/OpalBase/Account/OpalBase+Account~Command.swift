// OpalBase+Account~Command.swift

import Foundation

// MARK: - UTXO
extension _OpalBase.Account {
    /// Refreshes wallet-owned UTXOs through a public address reader.
    public func refreshUTXOSet(using service: OpalBase.Network.AddressReader, usage: OpalBase.Key.DerivationPath.Usage? = nil) async throws -> UTXORefresh {
        try await OpalBase.Diagnostics.withTraceID {
            let fields = [
                OpalBaseDiagnostics.operationField("utxo_refresh"),
                OpalBaseDiagnostics.moduleField()
            ] + (usage.map { [OpalBaseDiagnostics.usageField($0)] } ?? [])
            OpalBaseDiagnostics.record(
                OpalBase.Diagnostics.Events.utxoRefreshStarted,
                category: OpalBase.Diagnostics.Categories.addressBook,
                fields: fields
            )
            do {
                let refresh = try await addressBook.refreshUTXOSet(using: service, usage: usage)
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.utxoRefreshSucceeded,
                    category: OpalBase.Diagnostics.Categories.addressBook,
                    fields: fields + [
                        OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.addressCount, refresh.utxosByAddress.count),
                        OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.utxoCount, refresh.utxosByAddress.values.reduce(0) { $0 + $1.count })
                    ]
                )
                return UTXORefresh(refresh)
            } catch {
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.utxoRefreshFailed,
                    category: OpalBase.Diagnostics.Categories.addressBook,
                    fields: fields + OpalBaseDiagnostics.errorFields(for: error)
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
        try await OpalBase.Diagnostics.withTraceID {
            let fields = [
                OpalBaseDiagnostics.operationField("address_reserve"),
                OpalBaseDiagnostics.moduleField(),
                OpalBaseDiagnostics.usageField(.receiving)
            ]
            OpalBaseDiagnostics.record(
                OpalBase.Diagnostics.Events.addressReserveStarted,
                category: OpalBase.Diagnostics.Categories.addressBook,
                fields: fields
            )
            do {
                let address = try await DerivedAddress(reserveNextReceivingEntry())
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.addressReserveSucceeded,
                    category: OpalBase.Diagnostics.Categories.addressBook,
                    fields: fields
                )
                return address
            } catch {
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.addressReserveFailed,
                    category: OpalBase.Diagnostics.Categories.addressBook,
                    fields: fields + OpalBaseDiagnostics.errorFields(
                        for: error,
                        fallback: OpalBase.Diagnostics.ErrorCodes.addressReservationFailed
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
        try await OpalBase.Diagnostics.withTraceID {
            let fields = [
                OpalBaseDiagnostics.operationField("transaction_history_refresh"),
                OpalBaseDiagnostics.moduleField(),
                OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.includeUnconfirmed, includeUnconfirmed)
            ] + (usage.map { [OpalBaseDiagnostics.usageField($0)] } ?? [])
            OpalBaseDiagnostics.record(
                OpalBase.Diagnostics.Events.transactionHistoryRefreshStarted,
                category: OpalBase.Diagnostics.Categories.transaction,
                fields: fields
            )
            do {
                let changeSet = try await mapAddressBookError {
                    try await addressBook.refreshTransactionHistory(using: service,
                                                                    usage: usage,
                                                                    includeUnconfirmed: includeUnconfirmed,
                                                                    transactionReader: transactionReader)
                }
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.transactionHistoryRefreshSucceeded,
                    category: OpalBase.Diagnostics.Categories.transaction,
                    fields: fields + [
                        OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.transactionCount, changeSet.inserted.count + changeSet.updated.count)
                    ]
                )
                return changeSet
            } catch {
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.transactionHistoryRefreshFailed,
                    category: OpalBase.Diagnostics.Categories.transaction,
                    fields: fields + OpalBaseDiagnostics.errorFields(for: error)
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
        try await OpalBase.Diagnostics.withTraceID {
            let fields = [
                OpalBaseDiagnostics.operationField("transaction_confirmation_update"),
                OpalBaseDiagnostics.moduleField(),
                OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.transactionCount, transactionHashes.count)
            ]
            OpalBaseDiagnostics.record(
                OpalBase.Diagnostics.Events.transactionConfirmationRefreshStarted,
                category: OpalBase.Diagnostics.Categories.transaction,
                fields: fields
            )
            do {
                let changeSet = try await mapAddressBookError {
                    try await addressBook.updateTransactionConfirmations(using: handler,
                                                                         for: transactionHashes)
                }
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.transactionConfirmationRefreshSucceeded,
                    category: OpalBase.Diagnostics.Categories.transaction,
                    fields: fields + [
                        OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.confirmationCount, changeSet.updated.count)
                    ]
                )
                return changeSet
            } catch {
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.transactionConfirmationRefreshFailed,
                    category: OpalBase.Diagnostics.Categories.transaction,
                    fields: fields + OpalBaseDiagnostics.errorFields(for: error)
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
