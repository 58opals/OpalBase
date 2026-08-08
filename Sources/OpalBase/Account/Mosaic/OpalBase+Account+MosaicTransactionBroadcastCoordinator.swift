// OpalBase+Account+MosaicTransactionBroadcastCoordinator.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    /// Persists one exact complete transaction before any broadcast attempt.
    actor MosaicTransactionBroadcastCoordinator {
        let reservationReference: OpalFusion.Host.MosaicReservationReference
        let journal: MosaicAttemptJournal
        let transactionClient: OpalBase.Network.TransactionClient

        private var pendingTransaction: OpalFusion.Host.MosaicCompleteTransaction?
        private var broadcastIntentPersisted = false
        private var broadcastInFlight = false
        private var acceptedTransaction: (
            transaction: OpalFusion.Host.MosaicCompleteTransaction,
            hash: OpalBase.Transaction.Hash
        )?

        init(
            reservationReference: OpalFusion.Host.MosaicReservationReference,
            journal: MosaicAttemptJournal,
            transactionClient: OpalBase.Network.TransactionClient
        ) {
            self.reservationReference = reservationReference
            self.journal = journal
            self.transactionClient = transactionClient
        }

        func broadcast(
            _ completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
        ) async throws -> OpalBase.Transaction.Hash {
            if let acceptedTransaction {
                guard acceptedTransaction.transaction == completeTransaction else {
                    throw OpalBase.Account.MosaicHostFailure.conflictingBroadcast
                }
                return acceptedTransaction.hash
            }
            if let pendingTransaction {
                guard pendingTransaction == completeTransaction else {
                    throw OpalBase.Account.MosaicHostFailure.conflictingBroadcast
                }
                guard !broadcastInFlight else {
                    throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
                }
            } else {
                _ = try decodeExactTransaction(completeTransaction)
                pendingTransaction = completeTransaction
            }

            broadcastInFlight = true
            defer { broadcastInFlight = false }
            if !broadcastIntentPersisted {
                try await persist(
                    .broadcastIntent(
                        reference: reservationReference,
                        transaction: completeTransaction
                    )
                )
                broadcastIntentPersisted = true
            }
            try Task.checkCancellation()

            let transaction = try decodeExactTransaction(completeTransaction)
            let hash = try await transactionClient.broadcast(transaction: transaction)
            try await persist(
                .broadcastAccepted(
                    reference: reservationReference,
                    transaction: completeTransaction,
                    transactionHash: hash
                )
            )
            acceptedTransaction = (completeTransaction, hash)
            return hash
        }

        private func decodeExactTransaction(
            _ completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
        ) throws -> OpalBase.Transaction {
            do {
                let encoded = Data(completeTransaction.transactionBytes)
                let decoded = try OpalBase.Transaction.decode(from: encoded)
                guard decoded.bytesRead == encoded.count,
                      try decoded.transaction.encode() == encoded else {
                    throw OpalBase.Account.MosaicHostFailure.invalidCompleteTransaction
                }
                return decoded.transaction
            } catch let hostFailure as OpalBase.Account.MosaicHostFailure {
                throw hostFailure
            } catch {
                throw OpalBase.Account.MosaicHostFailure.invalidCompleteTransaction
            }
        }

        private func persist(
            _ record: MosaicAttemptJournal.Record
        ) async throws {
            do {
                try await journal.append(record)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw OpalBase.Account.MosaicHostFailure.journalPersistenceFailed
            }
        }
    }
}
#endif
