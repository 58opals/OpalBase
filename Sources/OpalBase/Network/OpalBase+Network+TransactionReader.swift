// OpalBase+Network+TransactionReader.swift

import Foundation

extension _OpalBase.Network {
    public struct TransactionReader: Sendable {
        private let performFetchRawTransaction: @Sendable (OpalBase.Transaction.Hash) async throws -> Data

        public init(
            fetchRawTransaction: @escaping @Sendable (OpalBase.Transaction.Hash) async throws -> Data
        ) {
            self.performFetchRawTransaction = fetchRawTransaction
        }

        public init(_ reader: OpalBase.Network.Fulcrum.TransactionReader) {
            self.init(fetchRawTransaction: reader.fetchRawTransaction(for:))
        }

        init(_ reader: any OpalBase.Network.TransactionReadableClient) {
            self.init(fetchRawTransaction: reader.fetchRawTransaction(for:))
        }

        public func fetchRawTransaction(for transactionHash: OpalBase.Transaction.Hash) async throws -> Data {
            try await Data(performFetchRawTransaction(transactionHash))
        }
    }
}

extension _OpalBase.Network.TransactionReader: OpalBase.Network.TransactionReadableClient {}
