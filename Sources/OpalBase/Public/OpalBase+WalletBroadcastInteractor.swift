// OpalBase+WalletBroadcastInteractor.swift

public extension OpalBase {
    /// Broadcast lane for transaction relay and targeted post-broadcast confirmation reconciliation.
    struct WalletBroadcastInteractor: Sendable {
        private let transactionClient: OpalBase.Network.TransactionClient

        public init(transactionClient: OpalBase.Network.TransactionClient) {
            self.transactionClient = transactionClient
        }

        public init(
            profile: OpalBase.WalletSecurityProfile,
            transactionClient: OpalBase.Network.TransactionClient
        ) throws {
            try profile.requireBroadcastingAllowed()
            self.transactionClient = transactionClient
        }

        public func broadcast(
            _ transaction: OpalBase.Transaction
        ) async throws -> OpalBase.Transaction.Hash {
            try await transactionClient.broadcast(transaction: transaction)
        }

        public func fetchConfirmationStatus(
            for transactionHash: OpalBase.Transaction.Hash
        ) async throws -> OpalBase.Network.TransactionConfirmationStatus {
            try await transactionClient.fetchConfirmationStatus(for: transactionHash)
        }

        public func reconcileConfirmations(
            for transactionHashes: [OpalBase.Transaction.Hash],
            in account: OpalBase.Account
        ) async throws -> OpalBase.Transaction.History.ChangeSet {
            try await account.updateTransactionConfirmations(
                using: transactionClient,
                for: transactionHashes
            )
        }
    }
}
