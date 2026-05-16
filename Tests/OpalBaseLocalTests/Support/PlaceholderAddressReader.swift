// PlaceholderAddressReader.swift

import Foundation
@testable import OpalBase

struct PlaceholderAddressReader: OpalBase.Network.AddressReadable {
    func fetchBalance(
        for address: String,
        tokenFilter: OpalBase.Network.TokenFilter
    ) async throws -> OpalBase.Network.AddressBalance {
        throw PlaceholderNetworkError.notImplemented
    }

    func fetchUnspentOutputs(
        for address: String,
        tokenFilter: OpalBase.Network.TokenFilter
    ) async throws -> [OpalBase.Transaction.Output.Unspent] {
        throw PlaceholderNetworkError.notImplemented
    }

    func fetchHistory(
        for address: String,
        includeUnconfirmed: Bool
    ) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
        throw PlaceholderNetworkError.notImplemented
    }

    func fetchFirstUse(for address: String) async throws -> OpalBase.Network.AddressFirstUse? {
        throw PlaceholderNetworkError.notImplemented
    }

    func fetchMempoolTransactions(
        for address: String
    ) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
        throw PlaceholderNetworkError.notImplemented
    }

    func fetchScriptHash(for address: String) async throws -> String {
        throw PlaceholderNetworkError.notImplemented
    }

    func subscribeToAddress(
        _ address: String
    ) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: PlaceholderNetworkError.notImplemented)
        }
    }
}
