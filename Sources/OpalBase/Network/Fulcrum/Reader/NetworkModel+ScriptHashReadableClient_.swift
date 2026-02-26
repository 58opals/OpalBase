// NetworkModel+ScriptHashReadable_.swift

import Foundation

extension NetworkModel {
    public protocol ScriptHashReadableClient: Sendable {
        func fetchHistory(forScriptHash scriptHashHex: String, includeUnconfirmed: Bool) async throws -> [NetworkModel.TransactionHistoryEntryModel]
        func fetchUnspent(forScriptHash scriptHashHex: String, tokenFilter: NetworkModel.TokenFilter) async throws -> [TransactionModel.OutputModel.UnspentModel]
    }
}
