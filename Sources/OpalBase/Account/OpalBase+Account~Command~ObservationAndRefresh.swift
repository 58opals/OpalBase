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
                      timestamp: Date = .now,
                      mutationPermit: OpalBase.Network.ChainRefreshMutationPermit? = nil) async throws -> UTXOChangeSet {
        let changeSet = try await addressBook.applyMonitoringUTXOs(for: address, with: utxos, timestamp: timestamp, mutationPermit: mutationPermit)
        return UTXOChangeSet(changeSet)
    }

    func refreshMonitoringAddressChainState(
        for address: OpalBase.Address,
        using reader: OpalBase.Network.AddressReader,
        includeUnconfirmed: Bool,
        transactionReader: OpalBase.Network.TransactionReader?,
        mutationPermit: OpalBase.Network.ChainRefreshMutationPermit,
        didRefreshHistory: @Sendable (OpalBase.Transaction.History.ChangeSet) async -> Void,
        didRefreshUTXOs: @Sendable (UTXOChangeSet) async -> Void
    ) async throws {
        try await addressBook.chainRefreshCoordinator.performForAddress(address) {
            try Task.checkCancellation()
            guard mutationPermit.isCurrent else { throw CancellationError() }
            let utxos = try await reader.fetchUnspentOutputs(for: address.string, tokenFilter: .include)
            let history = try await self.addressBook.refreshTransactionHistory(for: address,
                                                                               using: reader,
                                                                               includeUnconfirmed: includeUnconfirmed,
                                                                               transactionReader: transactionReader,
                                                                               mutationPermit: mutationPermit)
            try Task.checkCancellation()
            guard mutationPermit.isCurrent else { throw CancellationError() }
            await didRefreshHistory(history)
            let changeSet = try await self.addressBook.applyMonitoringUTXOs(for: address,
                                                                            with: utxos,
                                                                            timestamp: .now,
                                                                            mutationPermit: mutationPermit)
            try Task.checkCancellation()
            guard mutationPermit.isCurrent else { throw CancellationError() }
            await didRefreshUTXOs(UTXOChangeSet(changeSet))
        }
    }

    func refreshMonitoringChainState(
        using reader: OpalBase.Network.AddressReader,
        includeUnconfirmed: Bool,
        transactionReader: OpalBase.Network.TransactionReader?,
        mutationPermit: OpalBase.Network.ChainRefreshMutationPermit,
        didRefresh: @Sendable (UTXORefresh, OpalBase.Transaction.History.ChangeSet) async -> Void
    ) async throws {
        try await addressBook.chainRefreshCoordinator.performExclusively {
            try Task.checkCancellation()
            guard mutationPermit.isCurrent else { throw CancellationError() }
            let utxos = try await self.addressBook.refreshUTXOSet(using: reader, mutationPermit: mutationPermit)
            let history = try await self.addressBook.refreshTransactionHistory(using: reader,
                                                                               includeUnconfirmed: includeUnconfirmed,
                                                                               transactionReader: transactionReader,
                                                                               mutationPermit: mutationPermit)
            try Task.checkCancellation()
            guard mutationPermit.isCurrent else { throw CancellationError() }
            await didRefresh(UTXORefresh(utxos), history)
        }
    }

    func refreshMonitoringTransactionConfirmations(using client: OpalBase.Network.TransactionClient,
                                                   mutationPermit: OpalBase.Network.ChainRefreshMutationPermit) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await addressBook.chainRefreshCoordinator.performExclusively {
            try Task.checkCancellation()
            guard mutationPermit.isCurrent else { throw CancellationError() }
            return try await self.addressBook.refreshTransactionConfirmations(using: client, mutationPermit: mutationPermit)
        }
    }
}

extension _OpalBase.Account {
    func refreshTransactionHistory(for address: OpalBase.Address,
                                   using service: OpalBase.Network.AddressReader,
                                   includeUnconfirmed: Bool = true,
                                   transactionReader: OpalBase.Network.TransactionReader? = nil,
                                   mutationPermit: OpalBase.Network.ChainRefreshMutationPermit? = nil) async throws -> OpalBase.Transaction.History.ChangeSet {
        try await addressBook.chainRefreshCoordinator.performForAddress(address) {
            if let mutationPermit, !mutationPermit.isCurrent { throw CancellationError() }
            return try await self.addressBook.refreshTransactionHistory(for: address,
                                                                         using: service,
                                                                         includeUnconfirmed: includeUnconfirmed,
                                                                         transactionReader: transactionReader,
                                                                         mutationPermit: mutationPermit)
        }
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
