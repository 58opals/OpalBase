// OpalBase+Account+MosaicNetworkAttestedTransactionClient.swift

#if os(macOS)
extension _OpalBase.Account {
    /// Broadcast capability whose production network identity is derived from one concrete Fulcrum client.
    struct MosaicNetworkAttestedTransactionClient: Sendable {
        let network: OpalBase.Network.Environment
        private let transactionClient: OpalBase.Network.TransactionClient

        init(_ client: OpalBase.Network.Fulcrum.TransactionClient) {
            network = client.network
            transactionClient = .init(client)
        }

        #if DEBUG
        /// Debug-only package-test seam. Production composition uses the concrete Fulcrum initializer.
        init(
            testingNetwork network: OpalBase.Network.Environment,
            transactionClient: OpalBase.Network.TransactionClient
        ) {
            self.network = network
            self.transactionClient = transactionClient
        }
        #endif

        func broadcast(
            transaction: OpalBase.Transaction
        ) async throws -> OpalBase.Transaction.Hash {
            try await transactionClient.broadcast(transaction: transaction)
        }
    }
}
#endif
