import OpalBaseCore
// OpalBase+Account+MosaicTransactionBroadcastCoordinator.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    /// Relays one exact host-committed transaction only after app approval.
    actor MosaicTransactionBroadcastCoordinator {
        let candidate: MosaicCommittedBroadcastCandidate
        let transactionClient: MosaicNetworkAttestedTransactionClient
        let requestApproval: RequestApproval
        let authorizeSend: (@Sendable (ApprovalRequest) -> Bool)?

        private var approvalPersisted: Bool
        private var broadcastIntentPersisted: Bool
        private var broadcastInFlight = false
        private var acceptedTransactionHash: OpalBase.Transaction.Hash?

        init(
            candidate: MosaicCommittedBroadcastCandidate,
            securityProfile: OpalBase.WalletSecurityProfile,
            transactionClient: MosaicNetworkAttestedTransactionClient,
            authorizeSend: (@Sendable (ApprovalRequest) -> Bool)? = nil,
            requestApproval: @escaping RequestApproval
        ) throws {
            try securityProfile.requireBroadcastingAllowed()
            guard transactionClient.network.supportsMosaicProfile(
                    candidate.profile
                  ),
                  candidate.reservationRequest.networkGenesisHash
                    == transactionClient.network.mosaicGenesisHash else {
                throw MosaicHostFailure.invalidNetworkBinding
            }
            guard candidate.claimBroadcastCoordinator() else {
                throw MosaicHostFailure.broadcastCandidateUnavailable
            }

            self.candidate = candidate
            self.transactionClient = transactionClient
            self.requestApproval = requestApproval
            self.authorizeSend = authorizeSend
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
            let exactTransaction = try MosaicExactTransaction(
                candidate.completeTransaction
            )
            let request = ApprovalRequest(
                reservationRequest: candidate.reservationRequest,
                reservationReference: candidate.reservationReference,
                completeTransaction: candidate.completeTransaction,
                profile: candidate.profile, network: transactionClient.network
            )
            let sendAuthorization = OpalBase.Network.TransactionSendAuthorization { [authorizeSend] in
                authorizeSend?(request) == true
            }

            if !broadcastIntentPersisted && !sendAuthorization.isAuthorized() {
                throw OpalBase.Account.MosaicHostFailure.broadcastNotApproved
            }
            if !approvalPersisted {
                let decision: ApprovalDecision
                do {
                    decision = try await requestApproval(
                        .init(
                            reservationRequest: candidate.reservationRequest,
                            reservationReference: candidate.reservationReference,
                            completeTransaction: candidate.completeTransaction,
                            profile: candidate.profile,
                            network: transactionClient.network
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
                guard sendAuthorization.isAuthorized() else {
                    throw OpalBase.Account.MosaicHostFailure.broadcastNotApproved
                }
                try await persist(
                    .broadcastApproved(
                        reference: candidate.reservationReference,
                        transaction: candidate.completeTransaction
                    )
                )
                approvalPersisted = true
            }

            if broadcastIntentPersisted {
                switch try await transactionClient.presence(
                    of: exactTransaction
                ) {
                case let .present(observation):
                    try await persist(
                        .broadcastAccepted(
                            reference: candidate.reservationReference,
                            transaction: candidate.completeTransaction,
                            transactionHash: observation.transactionHash
                        )
                    )
                    acceptedTransactionHash = observation.transactionHash
                    return observation.transactionHash
                case .authoritativeAbsence:
                    break
                case .unknown:
                    throw OpalBase.Account.MosaicHostFailure
                        .reconciliationRequired
                }
            } else {
                try Task.checkCancellation()
                try await persist(
                    .broadcastIntent(
                        reference: candidate.reservationReference,
                        transaction: candidate.completeTransaction
                    )
                )
                broadcastIntentPersisted = true
                try Task.checkCancellation()
            }

            let hash: OpalBase.Transaction.Hash
            do {
                hash = try await transactionClient.broadcast(
                    transaction: exactTransaction.transaction, authorization: sendAuthorization
                )
            } catch is OpalBase.Network.TransactionSendAuthorization.Failure {
                throw OpalBase.Account.MosaicHostFailure.broadcastNotApproved
            }
            guard hash == exactTransaction.hash else {
                throw OpalBase.Account.MosaicHostFailure.reconciliationRequired
            }
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
