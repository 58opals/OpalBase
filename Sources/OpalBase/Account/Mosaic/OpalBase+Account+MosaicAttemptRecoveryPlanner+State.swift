// OpalBase+Account+MosaicAttemptRecoveryPlanner+State.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account.MosaicAttemptRecoveryPlanner {
    enum State {
        case reservationIntent(OpalFusion.Host.MosaicReservationReference)
        case reserved(OpalFusion.Host.MosaicReservationReference)
        case signingIntent(OpalFusion.Host.MosaicTransactionSigningRequest)
        case locallySigned(
            OpalFusion.Host.MosaicReservationReference,
            OpalFusion.Host.FinalizedTransaction
        )
        case releaseIntent(OpalFusion.Host.MosaicReservationReference)
        case released
        case commitIntent(
            OpalFusion.Host.MosaicReservationReference,
            OpalFusion.Host.MosaicCompleteTransaction
        )
        case committed(
            OpalFusion.Host.MosaicReservationReference,
            OpalFusion.Host.MosaicCompleteTransaction
        )
        case broadcastIntent(
            OpalFusion.Host.MosaicReservationReference,
            OpalFusion.Host.MosaicCompleteTransaction
        )
        case broadcastAccepted(OpalBase.Transaction.Hash)

        func applying(
            _ record: _OpalBase.Account.MosaicAttemptJournal.Record
        ) throws -> State {
            switch (self, record) {
            case let (.reservationIntent, .reserved(lease)):
                return .reserved(lease.reference)
            case let (.reservationIntent, .releaseIntent(reference)),
                 let (.reserved, .releaseIntent(reference)):
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
                return .released
            case let (.commitIntent(expectedReference, expectedTransaction),
                      .committed(reference, transaction)):
                guard expectedReference == reference,
                      expectedTransaction == transaction else {
                    throw Error.conflictingTransaction
                }
                return .committed(reference, transaction)
            case let (.committed(expectedReference, expectedTransaction),
                      .broadcastIntent(reference, transaction)):
                guard expectedReference == reference,
                      expectedTransaction == transaction else {
                    throw Error.conflictingTransaction
                }
                return .broadcastIntent(reference, transaction)
            case let (.broadcastIntent(expectedReference, expectedTransaction),
                      .broadcastAccepted(reference, transaction, hash)):
                guard expectedReference == reference,
                      expectedTransaction == transaction else {
                    throw Error.conflictingTransaction
                }
                return .broadcastAccepted(hash)
            default:
                throw Error.invalidTransition
            }
        }

        var plan: Plan {
            switch self {
            case let .reservationIntent(reference), let .reserved(reference):
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
            case let .committed(reference, transaction),
                 let .broadcastIntent(reference, transaction):
                .broadcast(reference: reference, transaction: transaction)
            case let .broadcastAccepted(hash):
                .complete(hash)
            }
        }
    }
}
#endif
