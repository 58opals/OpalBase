// Network+ScriptHashReadable_.swift

import Foundation

extension Network {
    public protocol ScriptHashReadable: Sendable {
        func fetchHistory(forScriptHash scriptHashHex: String, includeUnconfirmed: Bool) async throws -> [Network.TransactionHistoryEntry]
        func fetchUnspent(forScriptHash scriptHashHex: String, tokenFilter: Network.TokenFilter) async throws -> [Transaction.Output.Unspent]
    }
}
