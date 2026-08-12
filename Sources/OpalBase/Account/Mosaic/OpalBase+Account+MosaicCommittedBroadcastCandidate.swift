// OpalBase+Account+MosaicCommittedBroadcastCandidate.swift

#if os(macOS)
import OpalFusion
import Synchronization

extension _OpalBase.Account {
    /// Exact host-committed authority carried to the app-owned broadcast boundary.
    struct MosaicCommittedBroadcastCandidate: Sendable {
        final class CoordinatorClaim: Sendable {
            private let claimed = Mutex(false)

            func claim() -> Bool {
                claimed.withLock { claimed in
                    guard !claimed else { return false }
                    claimed = true
                    return true
                }
            }
        }

        let reservationRequest: OpalFusion.Host.MosaicReservationRequest
        let reservationReference: OpalFusion.Host.MosaicReservationReference
        let completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
        let profile: OpalFusion.Mosaic.Profile
        let journal: MosaicAttemptJournal
        let approvalPersisted: Bool
        let broadcastIntentPersisted: Bool
        private let coordinatorClaim: CoordinatorClaim

        fileprivate init(
            reservationRequest: OpalFusion.Host.MosaicReservationRequest,
            reservationReference: OpalFusion.Host.MosaicReservationReference,
            completeTransaction: OpalFusion.Host.MosaicCompleteTransaction,
            journal: MosaicAttemptJournal,
            approvalPersisted: Bool,
            broadcastIntentPersisted: Bool,
            coordinatorClaim: CoordinatorClaim = .init()
        ) throws {
            let supportedProfiles: [OpalFusion.Mosaic.Profile] = [
                .opalV0,
                .opalMainnetAlpha
            ]
            guard let profile = supportedProfiles.first(where: {
                $0.networkGenesisHash == reservationRequest.networkGenesisHash
                    && $0.transactionProfileIdentifier
                        == reservationRequest.transactionProfileIdentifier
            }),
                  reservationRequest.componentCount
                    == profile.rosterPolicy.componentCountPerContributor,
                  let contributionPolicy = MosaicProfileContributionPolicy(
                    profile: profile
                  ),
                  contributionPolicy.accepts(
                    feeRateSatoshisPerByte:
                        reservationRequest.feeRateSatoshisPerByte,
                    minimumExcessFeeSatoshis:
                        reservationRequest.minimumExcessFeeSatoshis,
                    maximumExcessFeeSatoshis:
                        reservationRequest.maximumExcessFeeSatoshis,
                    requiredExcessFeeSatoshis:
                        reservationRequest.requiredExcessFeeSatoshis
                  ) else {
                throw MosaicHostFailure.broadcastCandidateUnavailable
            }

            self.reservationRequest = reservationRequest
            self.reservationReference = reservationReference
            self.completeTransaction = completeTransaction
            self.profile = profile
            self.journal = journal
            self.approvalPersisted = approvalPersisted
            self.broadcastIntentPersisted = broadcastIntentPersisted
            self.coordinatorClaim = coordinatorClaim
        }

        init(
            recoveryAuthority _: MosaicAttemptRecoveryGate.RecoveryAuthority,
            reservationRequest: OpalFusion.Host.MosaicReservationRequest,
            reservationReference: OpalFusion.Host.MosaicReservationReference,
            completeTransaction: OpalFusion.Host.MosaicCompleteTransaction,
            journal: MosaicAttemptJournal,
            approvalPersisted: Bool,
            broadcastIntentPersisted: Bool
        ) throws {
            try self.init(
                reservationRequest: reservationRequest,
                reservationReference: reservationReference,
                completeTransaction: completeTransaction,
                journal: journal,
                approvalPersisted: approvalPersisted,
                broadcastIntentPersisted: broadcastIntentPersisted
            )
        }

        func claimBroadcastCoordinator() -> Bool {
            coordinatorClaim.claim()
        }
    }
}

extension _OpalBase.Account.MosaicTransactionHostActor {
    func makeCommittedBroadcastCandidate() throws
        -> OpalBase.Account.MosaicCommittedBroadcastCandidate {
        guard lifecycle == .committed,
              let reservationRequest,
              let reservationLease,
              let committedCompleteTransaction else {
            throw OpalBase.Account.MosaicHostFailure.broadcastCandidateUnavailable
        }
        return try .init(
            reservationRequest: reservationRequest,
            reservationReference: reservationLease.reference,
            completeTransaction: committedCompleteTransaction,
            journal: attemptJournal,
            approvalPersisted: false,
            broadcastIntentPersisted: false,
            coordinatorClaim: broadcastCoordinatorClaim
        )
    }
}
#endif
