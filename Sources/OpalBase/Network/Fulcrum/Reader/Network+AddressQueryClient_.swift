// Network+AddressQueryClient_.swift

import Foundation

extension Network {
    public protocol AddressQueryClient: Sendable {
        func fetchBalance(for address: String, tokenFilter: TokenFilter) async throws -> AddressBalance
        func fetchUnspentOutputs(for address: String, tokenFilter: TokenFilter) async throws -> [Transaction.Output.Unspent]
        func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [TransactionHistoryEntry]
        func fetchFirstUse(for address: String) async throws -> AddressFirstUse?
        func fetchMempoolTransactions(for address: String) async throws -> [TransactionHistoryEntry]
        func fetchScriptHash(for address: String) async throws -> String
    }
}
