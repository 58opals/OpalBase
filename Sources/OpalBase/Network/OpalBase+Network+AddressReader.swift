// OpalBase+Network+AddressReader.swift

import Foundation

extension _OpalBase.Network {
    public struct AddressReader: Sendable {
        private let fetchBalanceHandler: @Sendable (String, OpalBase.Network.TokenFilter) async throws -> OpalBase.Network.AddressBalance
        private let fetchUnspentOutputsHandler: @Sendable (String, OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent]
        private let fetchHistoryHandler: @Sendable (String, Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry]
        private let fetchFirstUseHandler: @Sendable (String) async throws -> OpalBase.Network.AddressFirstUse?
        private let fetchMempoolTransactionsHandler: @Sendable (String) async throws -> [OpalBase.Network.TransactionHistoryEntry]
        private let fetchScriptHashHandler: @Sendable (String) async throws -> String
        private let subscribeToAddressHandler: @Sendable (String) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error>

        public init(
            fetchBalance: @escaping @Sendable (String, OpalBase.Network.TokenFilter) async throws -> OpalBase.Network.AddressBalance,
            fetchUnspentOutputs: @escaping @Sendable (String, OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent],
            fetchHistory: @escaping @Sendable (String, Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry],
            fetchFirstUse: @escaping @Sendable (String) async throws -> OpalBase.Network.AddressFirstUse?,
            fetchMempoolTransactions: @escaping @Sendable (String) async throws -> [OpalBase.Network.TransactionHistoryEntry],
            fetchScriptHash: @escaping @Sendable (String) async throws -> String,
            subscribeToAddress: @escaping @Sendable (String) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error>
        ) {
            self.fetchBalanceHandler = fetchBalance
            self.fetchUnspentOutputsHandler = fetchUnspentOutputs
            self.fetchHistoryHandler = fetchHistory
            self.fetchFirstUseHandler = fetchFirstUse
            self.fetchMempoolTransactionsHandler = fetchMempoolTransactions
            self.fetchScriptHashHandler = fetchScriptHash
            self.subscribeToAddressHandler = subscribeToAddress
        }

        public init(_ reader: OpalBase.Network.Fulcrum.AddressReader) {
            self.init(
                fetchBalance: { address, tokenFilter in
                    try await reader.fetchBalance(for: address, tokenFilter: tokenFilter)
                },
                fetchUnspentOutputs: { address, tokenFilter in
                    try await reader.fetchUnspentOutputs(for: address, tokenFilter: tokenFilter)
                },
                fetchHistory: { address, includeUnconfirmed in
                    try await reader.fetchHistory(for: address, includeUnconfirmed: includeUnconfirmed)
                },
                fetchFirstUse: { address in
                    try await reader.fetchFirstUse(for: address)
                },
                fetchMempoolTransactions: { address in
                    try await reader.fetchMempoolTransactions(for: address)
                },
                fetchScriptHash: { address in
                    try await reader.fetchScriptHash(for: address)
                },
                subscribeToAddress: { address in
                    try await reader.subscribeToAddress(address)
                }
            )
        }

        init(_ reader: any OpalBase.Network.AddressReadable) {
            self.init(
                fetchBalance: { address, tokenFilter in
                    try await reader.fetchBalance(for: address, tokenFilter: tokenFilter)
                },
                fetchUnspentOutputs: { address, tokenFilter in
                    try await reader.fetchUnspentOutputs(for: address, tokenFilter: tokenFilter)
                },
                fetchHistory: { address, includeUnconfirmed in
                    try await reader.fetchHistory(for: address, includeUnconfirmed: includeUnconfirmed)
                },
                fetchFirstUse: { address in
                    try await reader.fetchFirstUse(for: address)
                },
                fetchMempoolTransactions: { address in
                    try await reader.fetchMempoolTransactions(for: address)
                },
                fetchScriptHash: { address in
                    try await reader.fetchScriptHash(for: address)
                },
                subscribeToAddress: { address in
                    try await reader.subscribeToAddress(address)
                }
            )
        }

        public func fetchBalance(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> OpalBase.Network.AddressBalance {
            try await fetchBalanceHandler(address, tokenFilter)
        }

        public func fetchUnspentOutputs(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent] {
            try await fetchUnspentOutputsHandler(address, tokenFilter)
        }

        public func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
            try await fetchHistoryHandler(address, includeUnconfirmed)
        }

        public func fetchFirstUse(for address: String) async throws -> OpalBase.Network.AddressFirstUse? {
            try await fetchFirstUseHandler(address)
        }

        public func fetchMempoolTransactions(for address: String) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
            try await fetchMempoolTransactionsHandler(address)
        }

        public func fetchScriptHash(for address: String) async throws -> String {
            try await fetchScriptHashHandler(address)
        }

        public func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error> {
            try await subscribeToAddressHandler(address)
        }
    }
}

extension _OpalBase.Network.AddressReader: OpalBase.Network.AddressQueryClient {}
extension _OpalBase.Network.AddressReader: OpalBase.Network.AddressSubscriptionClient {}
