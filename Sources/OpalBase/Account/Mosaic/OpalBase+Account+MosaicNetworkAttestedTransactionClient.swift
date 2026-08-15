// OpalBase+Account+MosaicNetworkAttestedTransactionClient.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    /// Broadcast and uncached exact-presence capability from one concrete Fulcrum identity.
    struct MosaicNetworkAttestedTransactionClient: Sendable {
        let network: OpalBase.Network.Environment
        private let transactionClient: OpalBase.Network.TransactionClient
        private let fetchFreshDetailedTransaction: @Sendable (
            OpalBase.Transaction.Hash
        ) async throws -> OpalBase.Transaction.Detail

        init(_ client: OpalBase.Network.Fulcrum.TransactionClient) {
            network = client.network
            transactionClient = .init(client)
            fetchFreshDetailedTransaction = client
                .fetchFreshDetailedTransaction(for:)
        }

        #if DEBUG
        /// Debug-only package-test seam. Production composition uses the concrete Fulcrum initializer.
        init(
            testingNetwork network: OpalBase.Network.Environment,
            transactionClient: OpalBase.Network.TransactionClient,
            fetchFreshDetailedTransaction: @escaping @Sendable (
                OpalBase.Transaction.Hash
            ) async throws -> OpalBase.Transaction.Detail = { _ in
                throw OpalBase.Network.Error(
                    reason: .server(code: -5),
                    message: "Transaction is authoritatively absent."
                )
            }
        ) {
            self.network = network
            self.transactionClient = transactionClient
            self.fetchFreshDetailedTransaction = fetchFreshDetailedTransaction
        }
        #endif

        func broadcast(
            transaction: OpalBase.Transaction
        ) async throws -> OpalBase.Transaction.Hash {
            try await transactionClient.broadcast(transaction: transaction)
        }

        func presence(
            of exactTransaction: MosaicExactTransaction
        ) async throws -> MosaicTransactionPresence {
            let detail: OpalBase.Transaction.Detail
            do {
                detail = try await fetchFreshDetailedTransaction(
                    exactTransaction.hash
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as OpalBase.Network.Error {
                if case let .server(code) = failure.reason, code == -5 {
                    return .authoritativeAbsence
                }
                if failure.reason == .decoding
                    || failure.reason == .protocolViolation {
                    return .unknown(.invalidChainMetadata)
                }
                return .unknown(.unavailable)
            } catch {
                return .unknown(.unavailable)
            }

            guard detail.hash == exactTransaction.hash,
                  detail.rawTransactionData == exactTransaction.bytes,
                  detail.size == UInt32(exactly: exactTransaction.bytes.count),
                  (try? detail.transaction.encode()) == exactTransaction.bytes else {
                return .unknown(.exactTransactionMismatch)
            }

            let confirmations = detail.confirmations ?? 0
            guard let observation = MosaicTransactionPresence.Observation(
                transactionHash: detail.hash,
                transactionBytes: detail.rawTransactionData,
                blockHash: detail.blockHash,
                confirmations: confirmations
            ) else {
                return .unknown(.invalidChainMetadata)
            }
            return .present(observation)
        }
    }
}
#endif
