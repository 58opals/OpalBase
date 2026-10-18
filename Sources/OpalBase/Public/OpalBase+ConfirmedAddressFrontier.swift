import Foundation

public extension OpalBase {
    /// Current, process-local evidence from a fresh consecutive-unused history scan. Local
    /// allocation, mempool entries and balances cannot advance either branch. Provider history
    /// and confirmation status remain trusted inputs; this is not independent chain validation.
    struct ConfirmedAddressFrontier: Sendable {
        public let accountID: Data
        public let network: Network.Environment
        public let receivingHighestIndex: Int64
        public let changeHighestIndex: Int64
        public let observedAt: Date
        public let revision: UUID
        public static let gap = 20
    }
}

public extension OpalBase.Account {
    func invalidateConfirmedAddressFrontier() async { await addressBook.invalidateConfirmedAddressFrontier() }

    func refreshConfirmedAddressFrontier(network: OpalBase.Network.Environment,
                                         using chain: OpalBase.WalletPublicChainOperations) async throws -> OpalBase.ConfirmedAddressFrontier {
        try await addressBook.chainRefreshCoordinator.performExclusively {
            try await self.addressBook.refreshConfirmedAddressFrontier(accountID: self.id, network: network, using: chain)
        }
    }

    /// The caller durably retains its issued high-water/request binding before disclosure. An
    /// address is never claimed to be new merely because this process has not reserved it.
    func boundedReceivingAddress(at index: UInt32,
                                 frontier: OpalBase.ConfirmedAddressFrontier) async throws -> DerivedAddress {
        try await addressBook.boundedReceivingAddress(at: index, frontier: frontier, accountID: id)
    }

    func prepareBoundedSpend(_ payment: Payment, frontier: OpalBase.ConfirmedAddressFrontier,
                             feePolicy: OpalBase.Wallet.FeePolicy = .init()) async throws -> SpendPlan {
        guard payment.recipients.allSatisfy({ $0.address.network == frontier.network }) else {
            throw OpalBase.BCHSubmissionError.networkMismatch
        }
        let entry = try await addressBook.boundedChangeEntry(frontier: frontier, accountID: id)
        return try await prepareSpend(payment, feePolicy: feePolicy, boundedChangeEntry: entry, boundedFrontier: frontier)
    }
}

extension OpalBase.Address.Book {
    func invalidateConfirmedAddressFrontier() { isConfirmedFrontierCurrent = false }

    func bindBoundedReservation(_ reservation: SpendReservation, frontier: OpalBase.ConfirmedAddressFrontier) throws {
        guard isConfirmedFrontierCurrent, confirmedAddressFrontier?.revision == frontier.revision,
              reservation.changeEntry.derivationPath.index == UInt32(frontier.changeHighestIndex + 1) else {
            throw OpalBase.BCHSubmissionError.staleFrontier
        }
        try validateExactReservation(reservation)
        boundedBCHFrontierRevisions[reservation.id] = frontier.revision
    }

    func refreshConfirmedAddressFrontier(accountID: Data, network: OpalBase.Network.Environment,
                                         using chain: OpalBase.WalletPublicChainOperations) async throws -> OpalBase.ConfirmedAddressFrontier {
        let previous = confirmedAddressFrontier
        isConfirmedFrontierCurrent = false
        var highest: [OpalBase.Key.DerivationPath.Usage: Int64] = [:]
        for usage in [OpalBase.Key.DerivationPath.Usage.receiving, .change] {
            var index: UInt32 = 0
            var gap = 0
            var confirmed: Int64 = -1
            while gap < OpalBase.ConfirmedAddressFrontier.gap {
                try Task.checkCancellation()
                let derived = try generateAddress(at: index, for: usage)
                let address = try OpalBase.Address(script: derived.lockingScript, network: network)
                let history = try await chain.addressReader.fetchHistory(for: address.string, includeUnconfirmed: false)
                var hasConfirmedHistory = false
                for entry in history where entry.blockHeight > 0 {
                    let hash = try OpalBase.Network.decodeTransactionHash(from: entry.transactionIdentifier)
                    let status = try await chain.transactionClient.fetchConfirmationStatus(for: hash)
                    try status.validateConsistency()
                    guard status.transactionHash == hash, status.transactionHeight == entry.blockHeight,
                          let confirmations = status.confirmations, confirmations > 0 else {
                        throw OpalBase.BCHSubmissionError.staleFrontier
                    }
                    hasConfirmedHistory = true
                }
                if hasConfirmedHistory { confirmed = Int64(index); gap = 0 } else { gap += 1 }
                guard index < HardenedIndex.maxUnhardenedValue else { throw Error.indexOutOfBounds }
                index += 1
            }
            highest[usage] = confirmed
        }
        let sameBound = previous?.accountID == accountID && previous?.network == network &&
            previous?.receivingHighestIndex == highest[.receiving] && previous?.changeHighestIndex == highest[.change]
        let frontier = OpalBase.ConfirmedAddressFrontier(accountID: accountID, network: network,
            receivingHighestIndex: highest[.receiving] ?? -1, changeHighestIndex: highest[.change] ?? -1,
            observedAt: Date(), revision: sameBound ? previous!.revision : UUID())
        confirmedAddressFrontier = frontier
        isConfirmedFrontierCurrent = true
        return frontier
    }

    func requireCurrentFrontier(_ frontier: OpalBase.ConfirmedAddressFrontier, accountID: Data) throws {
        guard isConfirmedFrontierCurrent, frontier.accountID == accountID, confirmedAddressFrontier?.revision == frontier.revision else {
            throw OpalBase.BCHSubmissionError.staleFrontier
        }
    }

    func boundedReceivingAddress(at index: UInt32, frontier: OpalBase.ConfirmedAddressFrontier,
                                 accountID: Data) async throws -> OpalBase.Account.DerivedAddress {
        try requireCurrentFrontier(frontier, accountID: accountID)
        guard Int64(index) <= frontier.receivingHighestIndex + Int64(OpalBase.ConfirmedAddressFrontier.gap),
              index <= HardenedIndex.maxUnhardenedValue else { throw OpalBase.BCHSubmissionError.addressAllocationBlocked }
        try await ensureEntry(at: index, usage: .receiving)
        try requireCurrentFrontier(frontier, accountID: accountID)
        let address = try generateAddress(at: index, for: .receiving)
        return .init(address: try OpalBase.Address(script: address.lockingScript, network: frontier.network),
                     derivationPath: try createDerivationPath(usage: .receiving, index: index), createdAt: Date())
    }

    func boundedChangeEntry(frontier: OpalBase.ConfirmedAddressFrontier, accountID: Data) async throws -> Entry {
        try requireCurrentFrontier(frontier, accountID: accountID)
        guard let index = UInt32(exactly: frontier.changeHighestIndex + 1), index <= HardenedIndex.maxUnhardenedValue else {
            throw OpalBase.BCHSubmissionError.addressAllocationBlocked
        }
        try await ensureEntry(at: index, usage: .change)
        try requireCurrentFrontier(frontier, accountID: accountID)
        guard let entry = listEntries(for: .change).first(where: { $0.derivationPath.index == index }), !entry.isReserved else {
            throw OpalBase.BCHSubmissionError.addressAllocationBlocked
        }
        return entry
    }

    private func ensureEntry(at index: UInt32, usage: OpalBase.Key.DerivationPath.Usage) async throws {
        let count = countEntries(for: usage)
        let needed = Int(index) + 1 - count
        if needed > 0 { try await generateEntries(for: usage, entryCount: needed, isUsed: false) }
    }
}
