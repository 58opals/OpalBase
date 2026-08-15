// OpalBase+Account+MosaicAttemptRecoveryPlanner+State.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account.MosaicAttemptRecoveryPlanner {
    enum State {
        case attemptBound(OpalBase.Account.MosaicAttemptBinding)
        case reservationIntent(OpalFusion.Host.MosaicReservationReference)
        case reservationPrepared(OpalFusion.Host.MosaicReservationLease)
        case reserved(OpalFusion.Host.MosaicReservationReference)
        case signingIntent(OpalFusion.Host.MosaicTransactionSigningRequest)
        case locallySigned(
            OpalFusion.Host.MosaicReservationReference,
            OpalFusion.Host.FinalizedTransaction
        )
        case releaseIntent(OpalFusion.Host.MosaicReservationReference)
        case released(OpalFusion.Host.MosaicReservationReference)
        case commitIntent(
            OpalFusion.Host.MosaicReservationReference,
            OpalFusion.Host.MosaicCompleteTransaction
        )
        case committed(
            OpalFusion.Host.MosaicReservationReference,
            OpalFusion.Host.MosaicCompleteTransaction
        )
        case broadcastApproved(
            OpalFusion.Host.MosaicReservationReference,
            OpalFusion.Host.MosaicCompleteTransaction
        )
        case unapprovedBroadcastIntent(
            OpalFusion.Host.MosaicReservationReference,
            OpalFusion.Host.MosaicCompleteTransaction
        )
        case approvedBroadcastIntent(
            OpalFusion.Host.MosaicReservationReference,
            OpalFusion.Host.MosaicCompleteTransaction
        )
        case broadcastAccepted(
            OpalFusion.Host.MosaicReservationReference,
            OpalFusion.Host.MosaicCompleteTransaction,
            OpalBase.Transaction.Hash
        )
        case chainTracking(OpalBase.Account.MosaicAttemptChainState)
        case terminal(OpalBase.Account.MosaicAttemptTerminalDisposition)

        func applying(
            _ record: _OpalBase.Account.MosaicAttemptJournal.Record
        ) throws -> State {
            switch (self, record) {
            case let (.attemptBound(binding), .reservationIntent(
                reference,
                _,
                _,
                _
            )) where binding.walletReservationReference == reference:
                return .reservationIntent(reference)
            case let (.attemptBound(binding), .releaseIntent(reference))
                where binding.walletReservationReference == reference:
                return .releaseIntent(reference)
            case let (.attemptBound(binding), .reservationPrepared(
                request,
                _,
                _,
                lease
            )) where binding.walletReservationReference == lease.reference
                    && Data(request.attemptIdentifier)
                        == binding.attemptIdentifier:
                return .reservationPrepared(lease)
            case let (.reservationPrepared(expected), .reserved(lease)):
                guard expected == lease else {
                    throw Error.invalidRecord
                }
                return .reserved(lease.reference)
            case let (.reservationIntent, .reserved(lease)):
                // Authenticated legacy snapshots already contain exact output identities.
                return .reserved(lease.reference)
            case let (.reservationIntent, .releaseIntent(reference)),
                 let (.reservationPrepared, .releaseIntent(reference)),
                 let (.reserved, .releaseIntent(reference)),
                 let (.signingIntent, .releaseIntent(reference)):
                return .releaseIntent(reference)
            case let (.reserved, .signingIntent(request)):
                return .signingIntent(request)
            case let (.signingIntent(request), .locallySigned(reference, transaction))
                where request.reservationReference == reference:
                return .locallySigned(reference, transaction)
            case let (.locallySigned, .commitIntent(reference, transaction)):
                return .commitIntent(reference, transaction)
            case let (.releaseIntent(expected), .released(reference))
                where expected == reference:
                return .released(reference)
            case let (.released(expected), .terminalDisposition(
                reference,
                transaction,
                disposition
            )):
                guard expected == reference,
                      transaction == nil,
                      disposition == .walletReleased else {
                    throw Error.invalidTransition
                }
                return .terminal(disposition)
            case let (.commitIntent(expectedReference, expectedTransaction),
                      .committed(reference, transaction)):
                guard expectedReference == reference,
                      expectedTransaction == transaction else {
                    throw Error.conflictingTransaction
                }
                return .committed(reference, transaction)
            case let (.committed(expectedReference, expectedTransaction),
                      .broadcastApproved(reference, transaction)):
                guard expectedReference == reference,
                      expectedTransaction == transaction else {
                    throw Error.conflictingTransaction
                }
                return .broadcastApproved(reference, transaction)
            case let (.committed(expectedReference, expectedTransaction),
                      .broadcastIntent(reference, transaction)):
                guard expectedReference == reference,
                      expectedTransaction == transaction else {
                    throw Error.conflictingTransaction
                }
                return .unapprovedBroadcastIntent(reference, transaction)
            case let (.broadcastApproved(expectedReference, expectedTransaction),
                      .broadcastIntent(reference, transaction)):
                guard expectedReference == reference,
                      expectedTransaction == transaction else {
                    throw Error.conflictingTransaction
                }
                return .approvedBroadcastIntent(reference, transaction)
            case let (.approvedBroadcastIntent(
                          expectedReference,
                          expectedTransaction
                      ), .broadcastAccepted(reference, transaction, hash)):
                guard expectedReference == reference,
                      expectedTransaction == transaction else {
                    throw Error.conflictingTransaction
                }
                return .broadcastAccepted(reference, transaction, hash)
            case let (.broadcastAccepted(
                expectedReference,
                expectedTransaction,
                expectedHash
            ), .chainObservation(reference, transaction, observation)):
                guard expectedReference == reference,
                      expectedTransaction == transaction,
                      expectedHash == observation.transactionHash else {
                    throw Error.conflictingTransaction
                }
                return .chainTracking(
                    Self.updatedChainState(
                        previous: nil,
                        reference: reference,
                        transaction: transaction,
                        transactionHash: expectedHash,
                        observation: observation
                    )
                )
            case let (.chainTracking(previous), .chainObservation(
                reference,
                transaction,
                observation
            )):
                guard previous.reference == reference,
                      previous.transaction == transaction,
                      previous.transactionHash == observation.transactionHash else {
                    throw Error.conflictingTransaction
                }
                return .chainTracking(
                    Self.updatedChainState(
                        previous: previous,
                        reference: reference,
                        transaction: transaction,
                        transactionHash: observation.transactionHash,
                        observation: observation
                    )
                )
            case let (.chainTracking(chainState), .terminalDisposition(
                reference,
                transaction,
                disposition
            )):
                guard chainState.reference == reference,
                      chainState.transaction == transaction,
                      case let .chainFinalized(
                          transactionHash,
                          blockHash,
                          confirmations
                      ) = disposition,
                      transactionHash == chainState.transactionHash,
                      let confirmed = chainState.latestObservation?
                        .confirmedIdentity,
                      confirmed.blockHash == blockHash,
                      confirmed.confirmations == confirmations else {
                    throw Error.invalidTransition
                }
                return .terminal(disposition)
            default:
                throw Error.invalidTransition
            }
        }

        var plan: Plan {
            switch self {
            case let .attemptBound(binding):
                .releaseBeforeSigning(binding.walletReservationReference)
            case let .reservationIntent(reference):
                .walletReconciliationHeld(reference)
            case let .reservationPrepared(lease):
                .releaseBeforeSigning(lease.reference)
            case let .reserved(reference):
                .releaseBeforeSigning(reference)
            case let .signingIntent(request):
                .reconcileSigningIntent(
                    reference: request.reservationReference,
                    request: request
                )
            case let .locallySigned(reference, transaction):
                .reconcileLocallySignedTransaction(
                    reference: reference,
                    transaction: transaction
                )
            case let .releaseIntent(reference):
                .finishRelease(reference)
            case .released:
                .released
            case let .commitIntent(reference, transaction):
                .finishCommit(reference: reference, transaction: transaction)
            case let .committed(reference, transaction):
                .broadcastApprovalRequired(
                    reference: reference,
                    transaction: transaction,
                    broadcastIntentPersisted: false
                )
            case let .unapprovedBroadcastIntent(reference, transaction):
                .broadcastReconciliationHeld(
                    reference: reference,
                    transaction: transaction
                )
            case let .broadcastApproved(reference, transaction):
                .resumeApprovedBroadcast(
                    reference: reference,
                    transaction: transaction,
                    broadcastIntentPersisted: false
                )
            case let .approvedBroadcastIntent(reference, transaction):
                .resumeApprovedBroadcast(
                    reference: reference,
                    transaction: transaction,
                    broadcastIntentPersisted: true
                )
            case let .broadcastAccepted(reference, transaction, hash):
                .reconcileChain(
                    .init(
                        reference: reference,
                        transaction: transaction,
                        transactionHash: hash,
                        latestObservation: nil,
                        holdReason: nil
                    )
                )
            case let .chainTracking(chainState):
                .reconcileChain(chainState)
            case let .terminal(disposition):
                .terminal(disposition)
            }
        }

        private static func updatedChainState(
            previous: OpalBase.Account.MosaicAttemptChainState?,
            reference: OpalFusion.Host.MosaicReservationReference,
            transaction: OpalFusion.Host.MosaicCompleteTransaction,
            transactionHash: OpalBase.Transaction.Hash,
            observation: OpalBase.Account.MosaicAttemptChainObservation
        ) -> OpalBase.Account.MosaicAttemptChainState {
            var holdReason = previous?.holdReason
            let priorPresentObservation: OpalBase.Account
                .MosaicAttemptChainObservation? = {
                    guard let latestObservation = previous?.latestObservation,
                          case .present = latestObservation.presence else {
                        return nil
                    }
                    return latestObservation
                }()

            switch observation.presence {
            case .authoritativeAbsence:
                holdReason = holdReason ?? .transactionDisappeared
            case .present:
                if let priorIdentity = priorPresentObservation?.confirmedIdentity {
                    guard let currentIdentity = observation.confirmedIdentity else {
                        holdReason = holdReason ?? .confirmationDepthRetreated
                        break
                    }
                    if currentIdentity.blockHash != priorIdentity.blockHash {
                        holdReason = holdReason ?? .blockIdentityChanged
                    } else if currentIdentity.confirmations
                                < priorIdentity.confirmations {
                        holdReason = holdReason ?? .confirmationDepthRetreated
                    }
                }
            }

            return .init(
                reference: reference,
                transaction: transaction,
                transactionHash: transactionHash,
                latestObservation: observation,
                holdReason: holdReason
            )
        }
    }
}
#endif
