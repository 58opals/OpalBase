// OpalBase+Network+AddressQueryClient_.swift

import Foundation

extension _OpalBase.Network {
    public protocol AddressQueryClient: Sendable {
        func fetchBalance(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> OpalBase.Network.AddressBalance
        func fetchUnspentOutputs(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent]
        func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry]
        func fetchFirstUse(for address: String) async throws -> OpalBase.Network.AddressFirstUse?
        func fetchMempoolTransactions(for address: String) async throws -> [OpalBase.Network.TransactionHistoryEntry]
        func fetchScriptHash(for address: String) async throws -> String
    }
}
