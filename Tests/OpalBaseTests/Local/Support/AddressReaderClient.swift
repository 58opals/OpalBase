// AddressReaderClient.swift

import Foundation
@testable import OpalBase

struct AddressReaderClient: NetworkModel.AddressReadable {
    let unspentByAddress: [String: [TransactionModel.OutputModel.UnspentModel]]

    func fetchBalance(for address: String, tokenFilter: NetworkModel.TokenFilter) async throws -> NetworkModel.AddressBalanceModel {
        NetworkModel.AddressBalanceModel(confirmed: 0, unconfirmed: 0)
    }

    func fetchUnspentOutputs(for address: String, tokenFilter: NetworkModel.TokenFilter) async throws -> [TransactionModel.OutputModel.UnspentModel] {
        unspentByAddress[address, default: .init()]
    }

    func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [NetworkModel.TransactionHistoryEntryModel] {
        .init()
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
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

