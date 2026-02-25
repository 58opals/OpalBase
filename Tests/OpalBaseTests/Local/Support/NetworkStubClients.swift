import Foundation
@testable import OpalBase

enum NetworkStubError: Swift.Error, Equatable {
    case forced(String)
}

actor WalletAddressReaderStub: Network.AddressReadable {
    private let balancesByAddress: [String: Network.AddressBalance]
    private let unspentByAddress: [String: [Transaction.Output.Unspent]]
    private let historyByAddress: [String: [Network.TransactionHistoryEntry]]
    private let updatesByAddress: [String: [Network.AddressSubscriptionUpdate]]
    private let subscriptionErrorsByAddress: [String: Swift.Error]
    private let keepSubscriptionsOpen: Bool

    private var remainingUnspentFailuresByAddress: [String: Int]

    private var balanceRequests: [String] = .init()
    private var unspentRequests: [String] = .init()
    private var historyRequests: [(address: String, includeUnconfirmed: Bool)] = .init()
    private var subscribeRequests: [String] = .init()

    init(
        balancesByAddress: [String: Network.AddressBalance] = .init(),
        unspentByAddress: [String: [Transaction.Output.Unspent]] = .init(),
        historyByAddress: [String: [Network.TransactionHistoryEntry]] = .init(),
        updatesByAddress: [String: [Network.AddressSubscriptionUpdate]] = .init(),
        subscriptionErrorsByAddress: [String: Swift.Error] = .init(),
        failUnspentCountByAddress: [String: Int] = .init(),
        keepSubscriptionsOpen: Bool = true
    ) {
        self.balancesByAddress = balancesByAddress
        self.unspentByAddress = unspentByAddress
        self.historyByAddress = historyByAddress
        self.updatesByAddress = updatesByAddress
        self.subscriptionErrorsByAddress = subscriptionErrorsByAddress
        self.remainingUnspentFailuresByAddress = failUnspentCountByAddress
        self.keepSubscriptionsOpen = keepSubscriptionsOpen
    }

    func fetchBalance(for address: String, tokenFilter: Network.TokenFilter) async throws -> Network.AddressBalance {
        balanceRequests.append(address)
        return balancesByAddress[address, default: .init(confirmed: 0, unconfirmed: 0)]
    }

    func fetchUnspentOutputs(for address: String, tokenFilter: Network.TokenFilter) async throws -> [Transaction.Output.Unspent] {
        unspentRequests.append(address)
        if let remaining = remainingUnspentFailuresByAddress[address], remaining > 0 {
            remainingUnspentFailuresByAddress[address] = remaining - 1
            throw NetworkStubError.forced("unspent-\(address)")
        }
        return unspentByAddress[address, default: .init()]
    }

    func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [Network.TransactionHistoryEntry] {
        historyRequests.append((address, includeUnconfirmed))
        return historyByAddress[address, default: .init()]
    }

    func fetchFirstUse(for address: String) async throws -> Network.AddressFirstUse? {
        nil
    }

    func fetchMempoolTransactions(for address: String) async throws -> [Network.TransactionHistoryEntry] {
        .init()
    }

    func fetchScriptHash(for address: String) async throws -> String {
        ""
    }

    func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<Network.AddressSubscriptionUpdate, any Swift.Error> {
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
            if !keepSubscriptionsOpen {
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

actor TransactionConfirmationClientStub: Network.TransactionConfirmationClient {
    private let confirmationsByIdentifier: [String: UInt?]
    private let statusesByHash: [Transaction.Hash: Network.TransactionConfirmationStatus]

    private var confirmationIdentifierRequests: [String] = .init()
    private var confirmationStatusRequests: [Transaction.Hash] = .init()

    init(
        confirmationsByIdentifier: [String: UInt?] = .init(),
        statusesByHash: [Transaction.Hash: Network.TransactionConfirmationStatus] = .init()
    ) {
        self.confirmationsByIdentifier = confirmationsByIdentifier
        self.statusesByHash = statusesByHash
    }

    func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt? {
        confirmationIdentifierRequests.append(transactionIdentifier)
        return confirmationsByIdentifier[transactionIdentifier] ?? nil
    }

    func fetchConfirmationStatus(for transactionHash: Transaction.Hash) async throws -> Network.TransactionConfirmationStatus {
        confirmationStatusRequests.append(transactionHash)
        return statusesByHash[transactionHash] ??
            .init(transactionHash: transactionHash, transactionHeight: nil, tipHeight: 0, confirmations: nil)
    }

    func readConfirmationStatusRequests() -> [Transaction.Hash] {
        confirmationStatusRequests
    }
}

actor BlockHeaderReaderStub: Network.BlockHeaderReadable {
    private let snapshots: [Network.BlockHeaderSnapshot]
    private let subscriptionError: Swift.Error?
    private let keepSubscriptionOpen: Bool

    init(
        snapshots: [Network.BlockHeaderSnapshot],
        subscriptionError: Swift.Error? = nil,
        keepSubscriptionOpen: Bool = true
    ) {
        self.snapshots = snapshots
        self.subscriptionError = subscriptionError
        self.keepSubscriptionOpen = keepSubscriptionOpen
    }

    func fetchTip() async throws -> Network.BlockHeaderSnapshot {
        snapshots.first ?? .init(height: 0, headerHexadecimal: String(repeating: "0", count: 160))
    }

    func subscribeToTip() async throws -> AsyncThrowingStream<Network.BlockHeaderSnapshot, any Swift.Error> {
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
            if !keepSubscriptionOpen {
                continuation.finish()
            }
        }
    }
}
