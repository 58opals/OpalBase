import Foundation
@testable import OpalBase

struct AddressReaderClient: Network.AddressReadable {
    let unspentByAddress: [String: [Transaction.Output.Unspent]]

    func fetchBalance(for address: String, tokenFilter: Network.TokenFilter) async throws -> Network.AddressBalance {
        Network.AddressBalance(confirmed: 0, unconfirmed: 0)
    }

    func fetchUnspentOutputs(for address: String, tokenFilter: Network.TokenFilter) async throws -> [Transaction.Output.Unspent] {
        unspentByAddress[address, default: .init()]
    }

    func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [Network.TransactionHistoryEntry] {
        .init()
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
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
