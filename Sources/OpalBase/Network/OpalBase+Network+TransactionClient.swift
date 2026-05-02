// OpalBase+Network+TransactionClient.swift

import Foundation

extension _OpalBase.Network {
    public struct TransactionClient: Sendable {
        private let broadcastTransactionHandler: @Sendable (String) async throws -> String
        private let fetchConfirmationsHandler: @Sendable (String) async throws -> UInt?
        private let fetchConfirmationStatusHandler: @Sendable (OpalBase.Transaction.Hash) async throws -> OpalBase.Network.TransactionConfirmationStatus

        public init(
            broadcastTransaction: @escaping @Sendable (String) async throws -> String,
            fetchConfirmations: @escaping @Sendable (String) async throws -> UInt?,
            fetchConfirmationStatus: @escaping @Sendable (OpalBase.Transaction.Hash) async throws -> OpalBase.Network.TransactionConfirmationStatus
        ) {
            self.broadcastTransactionHandler = broadcastTransaction
            self.fetchConfirmationsHandler = fetchConfirmations
            self.fetchConfirmationStatusHandler = fetchConfirmationStatus
        }

        public init(_ client: OpalBase.Network.Fulcrum.TransactionClient) {
            self.init(
                broadcastTransaction: client.broadcastTransaction(rawTransactionHexadecimal:),
                fetchConfirmations: client.fetchConfirmations(forTransactionIdentifier:),
                fetchConfirmationStatus: client.fetchConfirmationStatus(for:)
            )
        }

        init(_ client: any OpalBase.Network.TransactionHandling) {
            self.init(
                broadcastTransaction: client.broadcastTransaction(rawTransactionHexadecimal:),
                fetchConfirmations: client.fetchConfirmations(forTransactionIdentifier:),
                fetchConfirmationStatus: client.fetchConfirmationStatus(for:)
            )
        }

        init(confirmations client: any OpalBase.Network.TransactionConfirmationClient) {
            self.init(
                broadcastTransaction: { _ in
                    throw OpalBase.Network.Error(
                        reason: .protocolViolation,
                        message: "Broadcast is unavailable for this transaction client."
                    )
                },
                fetchConfirmations: client.fetchConfirmations(forTransactionIdentifier:),
                fetchConfirmationStatus: client.fetchConfirmationStatus(for:)
            )
        }

        public func broadcastTransaction(rawTransactionHexadecimal: String) async throws -> String {
            try await broadcastTransactionHandler(rawTransactionHexadecimal)
        }

        public func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt? {
            try await fetchConfirmationsHandler(transactionIdentifier)
        }

        public func fetchConfirmationStatus(for transactionHash: OpalBase.Transaction.Hash) async throws -> OpalBase.Network.TransactionConfirmationStatus {
            try await fetchConfirmationStatusHandler(transactionHash)
        }

        public func broadcast(transaction: OpalBase.Transaction) async throws -> OpalBase.Transaction.Hash {
            let rawTransactionData = try transaction.encode()
            let rawHexadecimal = rawTransactionData.hexadecimalString
            let transactionIdentifier = try await broadcastTransaction(rawTransactionHexadecimal: rawHexadecimal)
            return try OpalBase.Network.decodeBroadcastTransactionHash(
                from: transactionIdentifier,
                rawTransactionData: rawTransactionData
            )
        }
    }
}

extension _OpalBase.Network.TransactionClient: OpalBase.Network.TransactionBroadcastClient {}
extension _OpalBase.Network.TransactionClient: OpalBase.Network.TransactionConfirmationClient {}
