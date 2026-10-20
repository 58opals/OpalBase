// OpalBase+Network+TransactionClient.swift

import Foundation

extension _OpalBase.Network {
    public struct TransactionClient: Sendable {
        private let performBroadcastTransaction: @Sendable (String) async throws -> String
        private let performAuthorizedBroadcastTransaction: (@Sendable (String, OpalBase.Network.TransactionSendAuthorization) async throws -> String)?
        private let performFetchConfirmations: @Sendable (String) async throws -> UInt?
        private let performFetchConfirmationStatus: @Sendable (OpalBase.Transaction.Hash) async throws -> OpalBase.Network.TransactionConfirmationStatus

        public init(
            broadcastTransaction: @escaping @Sendable (String) async throws -> String,
            fetchConfirmations: @escaping @Sendable (String) async throws -> UInt?,
            fetchConfirmationStatus: @escaping @Sendable (OpalBase.Transaction.Hash) async throws -> OpalBase.Network.TransactionConfirmationStatus
        ) {
            self.performBroadcastTransaction = broadcastTransaction
            performAuthorizedBroadcastTransaction = nil
            self.performFetchConfirmations = fetchConfirmations
            self.performFetchConfirmationStatus = fetchConfirmationStatus
        }

        /// The guarded operation must revalidate synchronously after its last
        /// await or actor queue, immediately before handing bytes to transport.
        /// It must never substitute the unguarded operation when authorization fails.
        public init(
            broadcastTransaction: @escaping @Sendable (String) async throws -> String,
            authorizedBroadcastTransaction: @escaping @Sendable (String, OpalBase.Network.TransactionSendAuthorization) async throws -> String,
            fetchConfirmations: @escaping @Sendable (String) async throws -> UInt?,
            fetchConfirmationStatus: @escaping @Sendable (OpalBase.Transaction.Hash) async throws -> OpalBase.Network.TransactionConfirmationStatus
        ) {
            performBroadcastTransaction = broadcastTransaction
            performAuthorizedBroadcastTransaction = authorizedBroadcastTransaction
            performFetchConfirmations = fetchConfirmations
            performFetchConfirmationStatus = fetchConfirmationStatus
        }

        public init(_ client: OpalBase.Network.Fulcrum.TransactionClient) {
            self.init(
                broadcastTransaction: client.broadcastTransaction(rawTransactionHexadecimal:),
                authorizedBroadcastTransaction: client.broadcastTransaction(rawTransactionHexadecimal:authorization:),
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
            let rawTransactionData = try OpalBase.Network.decodeRawTransactionData(from: rawTransactionHexadecimal)
            let transactionHash = try await validatedBroadcast(
                rawTransactionHexadecimal: rawTransactionHexadecimal,
                rawTransactionData: rawTransactionData
            )
            return transactionHash.reverseOrder.hexadecimalString
        }

        public func fetchConfirmations(forTransactionIdentifier transactionIdentifier: String) async throws -> UInt? {
            try await performFetchConfirmations(transactionIdentifier)
        }

        public func fetchConfirmationStatus(for transactionHash: OpalBase.Transaction.Hash) async throws -> OpalBase.Network.TransactionConfirmationStatus {
            try await performFetchConfirmationStatus(transactionHash)
        }

        public func broadcast(transaction: OpalBase.Transaction) async throws -> OpalBase.Transaction.Hash {
            let rawTransactionData = try transaction.encode()
            let rawHexadecimal = rawTransactionData.hexadecimalString
            return try await validatedBroadcast(
                rawTransactionHexadecimal: rawHexadecimal,
                rawTransactionData: rawTransactionData
            )
        }

        public func broadcast(
            transaction: OpalBase.Transaction,
            authorization: OpalBase.Network.TransactionSendAuthorization
        ) async throws -> OpalBase.Transaction.Hash {
            try authorization.requireAuthorized()
            guard let performAuthorizedBroadcastTransaction else {
                throw OpalBase.Network.TransactionSendAuthorization.Failure.unavailable
            }
            let bytes = try transaction.encode()
            let identifier = try await performAuthorizedBroadcastTransaction(
                bytes.hexadecimalString, authorization
            )
            return try OpalBase.Network.decodeBroadcastTransactionHash(
                from: identifier, rawTransactionData: bytes
            )
        }

        private func validatedBroadcast(
            rawTransactionHexadecimal: String,
            rawTransactionData: Data
        ) async throws -> OpalBase.Transaction.Hash {
            let transactionIdentifier = try await performBroadcastTransaction(rawTransactionHexadecimal)
            return try OpalBase.Network.decodeBroadcastTransactionHash(
                from: transactionIdentifier,
                rawTransactionData: rawTransactionData
            )
        }
    }
}

extension _OpalBase.Network.TransactionClient: OpalBase.Network.TransactionBroadcastClient {}
extension _OpalBase.Network.TransactionClient: OpalBase.Network.TransactionConfirmationClient {}
