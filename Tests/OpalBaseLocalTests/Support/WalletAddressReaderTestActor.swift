// WalletAddressReaderTestActor.swift

import Foundation
@testable import OpalBase

actor WalletAddressReaderTestActor: OpalBase.Network.AddressReadable {
    private let balancesByAddress: [String: OpalBase.Network.AddressBalance]
    private let unspentByAddress: [String: [OpalBase.Transaction.Output.Unspent]]
    private let historyByAddress: [String: [OpalBase.Network.TransactionHistoryEntry]]
    private let updatesByAddress: [String: [OpalBase.Network.AddressSubscriptionUpdate]]
    private let subscriptionErrorsByAddress: [String: Swift.Error]
    private let shouldKeepSubscriptionsOpen: Bool

    private var remainingUnspentFailuresByAddress: [String: Int]

    private var balanceRequests: [String] = .init()
    private var unspentRequests: [String] = .init()
    private var historyRequests: [(address: String, includeUnconfirmed: Bool)] = .init()
    private var subscribeRequests: [String] = .init()
    private var subscriptionTerminationsByAddress: [String: Int] = .init()

    init(
        balancesByAddress: [String: OpalBase.Network.AddressBalance] = .init(),
        unspentByAddress: [String: [OpalBase.Transaction.Output.Unspent]] = .init(),
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

    func fetchUnspentOutputs(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent] {
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
            continuation.onTermination = { [weak self] _ in
                Task { await self?.recordSubscriptionTermination(for: address) }
            }
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

    func readSubscriptionTerminationCount(for address: String) -> Int {
        subscriptionTerminationsByAddress[address, default: 0]
    }

    private func recordSubscriptionTermination(for address: String) {
        subscriptionTerminationsByAddress[address, default: 0] += 1
    }
}
