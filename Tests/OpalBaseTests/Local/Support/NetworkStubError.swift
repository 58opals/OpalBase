// NetworkStubError.swift

import Foundation
@testable import OpalBase

enum NetworkStubError: Swift.Error, Equatable {
    case forced(String)
}

actor WalletAddressReaderTestActor: OpalBase.Network.AddressReadable {
    private let balancesByAddress: [String: OpalBase.Network.AddressBalance]
    private let unspentByAddress: [String: [OpalBase.Transaction.OutputModel.UnspentModel]]
    private let historyByAddress: [String: [OpalBase.Network.TransactionHistoryEntry]]
    private let updatesByAddress: [String: [OpalBase.Network.AddressSubscriptionUpdate]]
    private let subscriptionErrorsByAddress: [String: Swift.Error]
    private let shouldKeepSubscriptionsOpen: Bool

    private var remainingUnspentFailuresByAddress: [String: Int]

    private var balanceRequests: [String] = .init()
    private var unspentRequests: [String] = .init()
    private var historyRequests: [(address: String, includeUnconfirmed: Bool)] = .init()
    private var subscribeRequests: [String] = .init()

    init(
        balancesByAddress: [String: OpalBase.Network.AddressBalance] = .init(),
        unspentByAddress: [String: [OpalBase.Transaction.OutputModel.UnspentModel]] = .init(),
        historyByAddress: [String: [OpalBase.Network.TransactionHistoryEntry]] = .init(),
        updatesByAddress: [String: [OpalBase.Network.AddressSubscriptionUpdate]] = .init(),
        subscriptionErrorsByAddress: [String: Swift.Error] = .init(),
        failUnspentCountByAddress: [String: Int] = .init(),
        shouldKeepSubscriptionsOpen: Bool = true
    ) {
        self.balancesByAddress = balancesByAddress
        self.unspentByAddress = unspentByAddress
        self.historyByAddress = historyByAddress
        self.updatesByAddress = updatesByAddress
        self.subscriptionErrorsByAddress = subscriptionErrorsByAddress
        self.remainingUnspentFailuresByAddress = failUnspentCountByAddress
        self.shouldKeepSubscriptionsOpen = shouldKeepSubscriptionsOpen
    }

    func fetchBalance(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> OpalBase.Network.AddressBalance {
        balanceRequests.append(address)
        return balancesByAddress[address, default: .init(confirmed: 0, unconfirmed: 0)]
    }

    func fetchUnspentOutputs(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.OutputModel.UnspentModel] {
        unspentRequests.append(address)
        if let remaining = remainingUnspentFailuresByAddress[address], remaining > 0 {
            remainingUnspentFailuresByAddress[address] = remaining - 1
            throw NetworkStubError.forced("unspent-\(address)")
        }
        return unspentByAddress[address, default: .init()]
    }

    func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
        historyRequests.append((address, includeUnconfirmed))
        return historyByAddress[address, default: .init()]
    }

    func fetchFirstUse(for address: String) async throws -> OpalBase.Network.AddressFirstUse? {
        nil
    }

    func fetchMempoolTransactions(for address: String) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
        .init()
    }

    func fetchScriptHash(for address: String) async throws -> String {
        ""
    }

    func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error> {
        subscribeRequests.append(address)
        let updates = updatesByAddress[address, default: .init()]
        let failure = subscriptionErrorsByAddress[address]
        return AsyncThrowingStream { continuation in
            for update in updates {
                continuation.yield(update)
            }
            if let failure {
                continuation.finish(throwing: failure)
                return
            }
            if !shouldKeepSubscriptionsOpen {
                continuation.finish()
            }
        }
    }

    func readBalanceRequests() -> [String] {
        balanceRequests
    }

    func readHistoryRequests() -> [(address: String, includeUnconfirmed: Bool)] {
        historyRequests
    }

    func readSubscribeRequests() -> [String] {
        subscribeRequests
    }
}

actor TransactionConfirmationClientTestActor: OpalBase.Network.TransactionConfirmationClient {
    private let confirmationsByIdentifier: [String: UInt?]
    private let statusesByHash: [OpalBase.Transaction.HashModel: OpalBase.Network.TransactionConfirmationStatus]

    private var confirmationIdentifierRequests: [String] = .init()
    private var confirmationStatusRequests: [OpalBase.Transaction.HashModel] = .init()

    init(
        confirmationsByIdentifier: [String: UInt?] = .init(),
        statusesByHash: [OpalBase.Transaction.HashModel: OpalBase.Network.TransactionConfirmationStatus] = .init()
    ) {
        self.confirmationsByIdentifier = confirmationsByIdentifier
        self.statusesByHash = statusesByHash
    }

    func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt? {
        confirmationIdentifierRequests.append(transactionIdentifier)
        return confirmationsByIdentifier[transactionIdentifier] ?? nil
    }

    func fetchConfirmationStatus(for transactionHash: OpalBase.Transaction.HashModel) async throws -> OpalBase.Network.TransactionConfirmationStatus {
        confirmationStatusRequests.append(transactionHash)
        return statusesByHash[transactionHash] ??
            .init(transactionHash: transactionHash, transactionHeight: nil, tipHeight: 0, confirmations: nil)
    }

    func readConfirmationStatusRequests() -> [OpalBase.Transaction.HashModel] {
        confirmationStatusRequests
    }
}

actor BlockHeaderReaderTestActor: OpalBase.Network.BlockHeaderReadable {
    private let snapshots: [OpalBase.Network.BlockHeaderSnapshot]
    private let subscriptionError: Swift.Error?
    private let shouldKeepSubscriptionOpen: Bool

    init(
        snapshots: [OpalBase.Network.BlockHeaderSnapshot],
        subscriptionError: Swift.Error? = nil,
        shouldKeepSubscriptionOpen: Bool = true
    ) {
        self.snapshots = snapshots
        self.subscriptionError = subscriptionError
        self.shouldKeepSubscriptionOpen = shouldKeepSubscriptionOpen
    }

    func fetchTip() async throws -> OpalBase.Network.BlockHeaderSnapshot {
        snapshots.first ?? .init(height: 0, headerHexadecimal: String(repeating: "0", count: 160))
    }

    func subscribeToTip() async throws -> AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, any Swift.Error> {
        let snapshots = self.snapshots
        let subscriptionError = self.subscriptionError
        return AsyncThrowingStream { continuation in
            for snapshot in snapshots {
                continuation.yield(snapshot)
            }
            if let subscriptionError {
                continuation.finish(throwing: subscriptionError)
                return
            }
            if !shouldKeepSubscriptionOpen {
                continuation.finish()
            }
        }
    }
}

