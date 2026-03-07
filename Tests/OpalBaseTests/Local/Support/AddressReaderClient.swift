// AddressReaderClient.swift

import Foundation
@testable import OpalBase

struct AddressReaderClient: OpalBase.Network.AddressReadable {
    let unspentByAddress: [String: [OpalBase.Transaction.OutputModel.Unspent]]

    func fetchBalance(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> OpalBase.Network.AddressBalance {
        OpalBase.Network.AddressBalance(confirmed: 0, unconfirmed: 0)
    }

    func fetchUnspentOutputs(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.OutputModel.Unspent] {
        unspentByAddress[address, default: .init()]
    }

    func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
        .init()
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
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

