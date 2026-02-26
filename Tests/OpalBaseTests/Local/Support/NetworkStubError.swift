import Foundation
@testable import OpalBase

enum NetworkStubError: Swift.Error, Equatable {
    case forced(String)
}

actor WalletAddressReaderTestActor: NetworkModel.AddressReadable {
    private let balancesByAddress: [String: NetworkModel.AddressBalanceModel]
    private let unspentByAddress: [String: [TransactionModel.OutputModel.UnspentModel]]
    private let historyByAddress: [String: [NetworkModel.TransactionHistoryEntryModel]]
    private let updatesByAddress: [String: [NetworkModel.AddressSubscriptionUpdateModel]]
    private let subscriptionErrorsByAddress: [String: Swift.Error]
    private let shouldKeepSubscriptionsOpen: Bool

    private var remainingUnspentFailuresByAddress: [String: Int]

    private var balanceRequests: [String] = .init()
    private var unspentRequests: [String] = .init()
    private var historyRequests: [(address: String, includeUnconfirmed: Bool)] = .init()
    private var subscribeRequests: [String] = .init()

    init(
        balancesByAddress: [String: NetworkModel.AddressBalanceModel] = .init(),
        unspentByAddress: [String: [TransactionModel.OutputModel.UnspentModel]] = .init(),
        historyByAddress: [String: [NetworkModel.TransactionHistoryEntryModel]] = .init(),
        updatesByAddress: [String: [NetworkModel.AddressSubscriptionUpdateModel]] = .init(),
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

    func fetchBalance(for address: String, tokenFilter: NetworkModel.TokenFilter) async throws -> NetworkModel.AddressBalanceModel {
        balanceRequests.append(address)
        return balancesByAddress[address, default: .init(confirmed: 0, unconfirmed: 0)]
    }

    func fetchUnspentOutputs(for address: String, tokenFilter: NetworkModel.TokenFilter) async throws -> [TransactionModel.OutputModel.UnspentModel] {
        unspentRequests.append(address)
        if let remaining = remainingUnspentFailuresByAddress[address], remaining > 0 {
            remainingUnspentFailuresByAddress[address] = remaining - 1
            throw NetworkStubError.forced("unspent-\(address)")
        }
        return unspentByAddress[address, default: .init()]
    }

    func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [NetworkModel.TransactionHistoryEntryModel] {
        historyRequests.append((address, includeUnconfirmed))
        return historyByAddress[address, default: .init()]
    }

    func fetchFirstUse(for address: String) async throws -> NetworkModel.AddressFirstUseModel? {
        nil
    }

    func fetchMempoolTransactions(for address: String) async throws -> [NetworkModel.TransactionHistoryEntryModel] {
        .init()
    }

    func fetchScriptHash(for address: String) async throws -> String {
        ""
    }

    func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<NetworkModel.AddressSubscriptionUpdateModel, any Swift.Error> {
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

actor TransactionConfirmationClientTestActor: NetworkModel.TransactionConfirmationClient {
    private let confirmationsByIdentifier: [String: UInt?]
    private let statusesByHash: [TransactionModel.HashModel: NetworkModel.TransactionConfirmationStatusModel]

    private var confirmationIdentifierRequests: [String] = .init()
    private var confirmationStatusRequests: [TransactionModel.HashModel] = .init()

    init(
        confirmationsByIdentifier: [String: UInt?] = .init(),
        statusesByHash: [TransactionModel.HashModel: NetworkModel.TransactionConfirmationStatusModel] = .init()
    ) {
        self.confirmationsByIdentifier = confirmationsByIdentifier
        self.statusesByHash = statusesByHash
    }

    func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt? {
        confirmationIdentifierRequests.append(transactionIdentifier)
        return confirmationsByIdentifier[transactionIdentifier] ?? nil
    }

    func fetchConfirmationStatus(for transactionHash: TransactionModel.HashModel) async throws -> NetworkModel.TransactionConfirmationStatusModel {
        confirmationStatusRequests.append(transactionHash)
        return statusesByHash[transactionHash] ??
            .init(transactionHash: transactionHash, transactionHeight: nil, tipHeight: 0, confirmations: nil)
    }

    func readConfirmationStatusRequests() -> [TransactionModel.HashModel] {
        confirmationStatusRequests
    }
}

actor BlockHeaderReaderTestActor: NetworkModel.BlockHeaderReadable {
    private let snapshots: [NetworkModel.BlockHeaderSnapshotModel]
    private let subscriptionError: Swift.Error?
    private let shouldKeepSubscriptionOpen: Bool

    init(
        snapshots: [NetworkModel.BlockHeaderSnapshotModel],
        subscriptionError: Swift.Error? = nil,
        shouldKeepSubscriptionOpen: Bool = true
    ) {
        self.snapshots = snapshots
        self.subscriptionError = subscriptionError
        self.shouldKeepSubscriptionOpen = shouldKeepSubscriptionOpen
    }

    func fetchTip() async throws -> NetworkModel.BlockHeaderSnapshotModel {
        snapshots.first ?? .init(height: 0, headerHexadecimal: String(repeating: "0", count: 160))
    }

    func subscribeToTip() async throws -> AsyncThrowingStream<NetworkModel.BlockHeaderSnapshotModel, any Swift.Error> {
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
