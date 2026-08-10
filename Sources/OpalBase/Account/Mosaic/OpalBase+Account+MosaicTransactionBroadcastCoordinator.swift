// OpalBase+Account+MosaicTransactionBroadcastCoordinator.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    /// Relays one exact host-committed transaction only after app approval.
    actor MosaicTransactionBroadcastCoordinator {
        let candidate: MosaicCommittedBroadcastCandidate
        let expectedNetwork: OpalBase.Network.Environment
        let transactionClient: OpalBase.Network.TransactionClient
        let requestApproval: RequestApproval

        private var approvalPersisted: Bool
        private var broadcastIntentPersisted: Bool
        private var broadcastInFlight = false
        private var acceptedTransactionHash: OpalBase.Transaction.Hash?

        init(
            candidate: MosaicCommittedBroadcastCandidate,
            expectedNetwork: OpalBase.Network.Environment,
            securityProfile: OpalBase.WalletSecurityProfile,
            transactionClient: OpalBase.Network.TransactionClient,
            requestApproval: @escaping RequestApproval
        ) throws {
            try securityProfile.requireBroadcastingAllowed()
            guard expectedNetwork.supportsMosaicProfile(candidate.profile),
                  candidate.reservationRequest.networkGenesisHash
                    == expectedNetwork.mosaicGenesisHash else {
                throw MosaicHostFailure.invalidNetworkBinding
            }

            self.candidate = candidate
            self.expectedNetwork = expectedNetwork
            self.transactionClient = transactionClient
            self.requestApproval = requestApproval
            approvalPersisted = candidate.approvalPersisted
            broadcastIntentPersisted = candidate.broadcastIntentPersisted
        }

        func broadcast() async throws -> OpalBase.Transaction.Hash {
            if let acceptedTransactionHash { return acceptedTransactionHash }
            guard !broadcastInFlight else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }

            broadcastInFlight = true
            defer { broadcastInFlight = false }
            try Task.checkCancellation()
            let transaction = try decodeExactTransaction(
                candidate.completeTransaction
            )

            if !approvalPersisted {
                let decision: ApprovalDecision
                do {
                    decision = try await requestApproval(
                        .init(
                            reservationRequest: candidate.reservationRequest,
                            reservationReference: candidate.reservationReference,
                            completeTransaction: candidate.completeTransaction,
                            profile: candidate.profile,
                            network: expectedNetwork
                        )
                    )
                } catch let cancellation as CancellationError {
                    throw cancellation
                } catch {
                    throw OpalBase.Account.MosaicHostFailure
                        .broadcastNotApproved
                }
                try Task.checkCancellation()
                guard decision == .approved else {
                    throw OpalBase.Account.MosaicHostFailure
                        .broadcastNotApproved
                }
                try await persist(
                    .broadcastApproved(
                        reference: candidate.reservationReference,
                        transaction: candidate.completeTransaction
                    )
                )
                approvalPersisted = true
            }

            if !broadcastIntentPersisted {
                try Task.checkCancellation()
                try await persist(
                    .broadcastIntent(
                        reference: candidate.reservationReference,
                        transaction: candidate.completeTransaction
                    )
                )
                broadcastIntentPersisted = true
            }
            try Task.checkCancellation()

            let hash = try await transactionClient.broadcast(transaction: transaction)
            try await persist(
                .broadcastAccepted(
                    reference: candidate.reservationReference,
                    transaction: candidate.completeTransaction,
                    transactionHash: hash
                )
            )
            acceptedTransactionHash = hash
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
                try await candidate.journal.append(record)
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                throw OpalBase.Account.MosaicHostFailure.journalPersistenceFailed
            }
        }
    }
}
#endif
