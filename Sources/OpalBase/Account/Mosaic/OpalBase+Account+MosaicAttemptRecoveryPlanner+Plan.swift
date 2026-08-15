// OpalBase+Account+MosaicAttemptRecoveryPlanner+Plan.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account.MosaicAttemptRecoveryPlanner {
    enum Plan: Sendable, Equatable {
        case noAction
        case walletReconciliationHeld(
            OpalFusion.Host.MosaicReservationReference
        )
        case releaseBeforeSigning(OpalFusion.Host.MosaicReservationReference)
        case reconcileSigningIntent(
            reference: OpalFusion.Host.MosaicReservationReference,
            request: OpalFusion.Host.MosaicTransactionSigningRequest
        )
        case reconcileLocallySignedTransaction(
            reference: OpalFusion.Host.MosaicReservationReference,
            transaction: OpalFusion.Host.FinalizedTransaction
        )
        case finishRelease(OpalFusion.Host.MosaicReservationReference)
        case released
        case finishCommit(
            reference: OpalFusion.Host.MosaicReservationReference,
            transaction: OpalFusion.Host.MosaicCompleteTransaction
        )
        case broadcastApprovalRequired(
            reference: OpalFusion.Host.MosaicReservationReference,
            transaction: OpalFusion.Host.MosaicCompleteTransaction,
            broadcastIntentPersisted: Bool
        )
        case broadcastReconciliationHeld(
            reference: OpalFusion.Host.MosaicReservationReference,
            transaction: OpalFusion.Host.MosaicCompleteTransaction
        )
        case resumeApprovedBroadcast(
            reference: OpalFusion.Host.MosaicReservationReference,
            transaction: OpalFusion.Host.MosaicCompleteTransaction,
            broadcastIntentPersisted: Bool
        )
        case reconcileChain(OpalBase.Account.MosaicAttemptChainState)
        case terminal(OpalBase.Account.MosaicAttemptTerminalDisposition)
    }
}
#endif
