// OpalBase+Account+MosaicPrivateAlphaRecoveryOwner+Outcome.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account.MosaicPrivateAlphaRecoveryOwner {
    enum Outcome: Sendable {
        case walletReconciliationHeld(
            OpalFusion.Host.MosaicReservationReference
        )
        case locallySignedContinuation(
            reference: OpalFusion.Host.MosaicReservationReference,
            transaction: OpalFusion.Host.FinalizedTransaction
        )
        case broadcastApprovalRequired(
            OpalBase.Account.MosaicCommittedBroadcastCandidate
        )
        case resumeApprovedBroadcast(
            OpalBase.Account.MosaicCommittedBroadcastCandidate
        )
        case broadcastReconciliationHeld
        case chainReconciliationRequired(
            OpalBase.Account.MosaicAttemptChainState
        )
        case terminal(OpalBase.Account.MosaicAttemptTerminalDisposition)
    }
}
#endif
