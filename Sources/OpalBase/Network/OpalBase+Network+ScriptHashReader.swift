// OpalBase+Network+ScriptHashReader.swift

import Foundation

extension _OpalBase.Network {
    public struct ScriptHashReader: Sendable {
        private let fetchHistoryHandler: @Sendable (String, Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry]
        private let fetchUnspentHandler: @Sendable (String, OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent]

        public init(
            fetchHistory: @escaping @Sendable (String, Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry],
            fetchUnspent: @escaping @Sendable (String, OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent]
        ) {
            self.fetchHistoryHandler = fetchHistory
            self.fetchUnspentHandler = fetchUnspent
        }

        public init(_ reader: OpalBase.Network.Fulcrum.ScriptHashReader) {
            self.init(
                fetchHistory: reader.fetchHistory(forScriptHash:includeUnconfirmed:),
                fetchUnspent: reader.fetchUnspent(forScriptHash:tokenFilter:)
            )
        }

        init(_ reader: any OpalBase.Network.ScriptHashReadableClient) {
            self.init(
                fetchHistory: reader.fetchHistory(forScriptHash:includeUnconfirmed:),
                fetchUnspent: reader.fetchUnspent(forScriptHash:tokenFilter:)
            )
        }

        public func fetchHistory(
            forScriptHash scriptHashHex: String,
            includeUnconfirmed: Bool
        ) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
            try await fetchHistoryHandler(scriptHashHex, includeUnconfirmed)
        }

        public func fetchUnspent(
            forScriptHash scriptHashHex: String,
            tokenFilter: OpalBase.Network.TokenFilter
        ) async throws -> [OpalBase.Transaction.Output.Unspent] {
            try await fetchUnspentHandler(scriptHashHex, tokenFilter)
        }
    }
}

extension _OpalBase.Network.ScriptHashReader: OpalBase.Network.ScriptHashReadableClient {}
