// NetworkModel+AddressQueryClient_.swift

import Foundation

extension NetworkModel {
    public protocol AddressQueryClient: Sendable {
        func fetchBalance(for address: String, tokenFilter: TokenFilter) async throws -> AddressBalanceModel
        func fetchUnspentOutputs(for address: String, tokenFilter: TokenFilter) async throws -> [TransactionModel.OutputModel.UnspentModel]
        func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [TransactionHistoryEntryModel]
        func fetchFirstUse(for address: String) async throws -> AddressFirstUseModel?
        func fetchMempoolTransactions(for address: String) async throws -> [TransactionHistoryEntryModel]
        func fetchScriptHash(for address: String) async throws -> String
    }
}
