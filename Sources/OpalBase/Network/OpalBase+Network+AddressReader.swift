// OpalBase+Network+AddressReader.swift

import Foundation

extension _OpalBase.Network {
    public struct AddressReader: Sendable {
        private let performFetchBalance: @Sendable (String, OpalBase.Network.TokenFilter) async throws -> OpalBase.Network.AddressBalance
        private let performFetchUnspentOutputs: @Sendable (String, OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent]
        private let performFetchHistory: @Sendable (String, Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry]
        private let performFetchFirstUse: @Sendable (String) async throws -> OpalBase.Network.AddressFirstUse?
        private let performFetchMempoolTransactions: @Sendable (String) async throws -> [OpalBase.Network.TransactionHistoryEntry]
        private let performFetchScriptHash: @Sendable (String) async throws -> String
        private let performSubscribeToAddress: @Sendable (String) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error>

        public init(
            fetchBalance: @escaping @Sendable (String, OpalBase.Network.TokenFilter) async throws -> OpalBase.Network.AddressBalance,
            fetchUnspentOutputs: @escaping @Sendable (String, OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent],
            fetchHistory: @escaping @Sendable (String, Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry],
            fetchFirstUse: @escaping @Sendable (String) async throws -> OpalBase.Network.AddressFirstUse?,
            fetchMempoolTransactions: @escaping @Sendable (String) async throws -> [OpalBase.Network.TransactionHistoryEntry],
            fetchScriptHash: @escaping @Sendable (String) async throws -> String,
            subscribeToAddress: @escaping @Sendable (String) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error>
        ) {
            self.performFetchBalance = fetchBalance
            self.performFetchUnspentOutputs = fetchUnspentOutputs
            self.performFetchHistory = fetchHistory
            self.performFetchFirstUse = fetchFirstUse
            self.performFetchMempoolTransactions = fetchMempoolTransactions
            self.performFetchScriptHash = fetchScriptHash
            self.performSubscribeToAddress = subscribeToAddress
        }

        public init(_ reader: OpalBase.Network.Fulcrum.AddressReader) {
            self.init(reader as any OpalBase.Network.AddressReadable)
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
            try await performFetchBalance(address, tokenFilter)
        }

        public func fetchUnspentOutputs(for address: String, tokenFilter: OpalBase.Network.TokenFilter) async throws -> [OpalBase.Transaction.Output.Unspent] {
            try await performFetchUnspentOutputs(address, tokenFilter)
        }

        public func fetchHistory(for address: String, includeUnconfirmed: Bool) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
            try await performFetchHistory(address, includeUnconfirmed)
        }

        public func fetchFirstUse(for address: String) async throws -> OpalBase.Network.AddressFirstUse? {
            try await performFetchFirstUse(address)
        }

        public func fetchMempoolTransactions(for address: String) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
            try await performFetchMempoolTransactions(address)
        }

        public func fetchScriptHash(for address: String) async throws -> String {
            try await performFetchScriptHash(address)
        }

        public func subscribeToAddress(_ address: String) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error> {
            try await performSubscribeToAddress(address)
        }
    }
}

extension _OpalBase.Network.AddressReader: OpalBase.Network.AddressQueryClient {}
extension _OpalBase.Network.AddressReader: OpalBase.Network.AddressSubscriptionClient {}
