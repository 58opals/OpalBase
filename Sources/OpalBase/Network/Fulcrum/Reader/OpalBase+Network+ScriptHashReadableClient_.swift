// OpalBase+Network+ScriptHashReadableClient_.swift

import Foundation

extension _OpalBase.Network {
    public protocol ScriptHashReadableClient: Sendable {
        func fetchHistory(forScriptHash scriptHashHex: String, includeUnconfirmed: Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry]
        func fetchUnspent(forScriptHash scriptHashHex: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.OutputModel.Unspent]
    }
}

