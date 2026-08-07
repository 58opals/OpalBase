// OpalBase+Account+MosaicAttemptJournal+Record.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account.MosaicAttemptJournal {
    enum Record: Sendable, Equatable {
        case reservationIntent(
            reference: OpalFusion.Host.MosaicReservationReference,
            request: OpalFusion.Host.MosaicReservationRequest,
            selectedInputs: [SelectedInput],
            outputAmountsSatoshis: [UInt64]
        )
        case reserved(OpalFusion.Host.MosaicReservationLease)
        case signingIntent(OpalFusion.Host.MosaicTransactionSigningRequest)
        case locallySigned(
            reference: OpalFusion.Host.MosaicReservationReference,
            transaction: OpalFusion.Host.FinalizedTransaction
        )
        case releaseIntent(OpalFusion.Host.MosaicReservationReference)
        case released(OpalFusion.Host.MosaicReservationReference)
        case commitIntent(
            reference: OpalFusion.Host.MosaicReservationReference,
            transaction: OpalFusion.Host.MosaicCompleteTransaction
        )
        case committed(
            reference: OpalFusion.Host.MosaicReservationReference,
            transaction: OpalFusion.Host.MosaicCompleteTransaction
        )
        case broadcastIntent(
            reference: OpalFusion.Host.MosaicReservationReference,
            transaction: OpalFusion.Host.MosaicCompleteTransaction
        )
        case broadcastAccepted(
            reference: OpalFusion.Host.MosaicReservationReference,
            transaction: OpalFusion.Host.MosaicCompleteTransaction,
            transactionHash: OpalBase.Transaction.Hash
        )
    }
}
#endif
