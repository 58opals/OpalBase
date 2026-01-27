// Network+ScriptHashReadable_.swift

import Foundation

extension Network {
    public protocol ScriptHashReadable: Sendable {
        func fetchHistory(forScriptHash scriptHash: String, includeUnconfirmed: Bool) async throws -> [TransactionHistoryEntry]
    }
}
