// OpalBase+Account+MosaicAttemptRecoveryGate+Model.swift

#if os(macOS)
extension _OpalBase.Account.MosaicAttemptRecoveryGate {
    enum Outcome: Sendable {
        case noAction
        case released
        case walletReconciliationRequired(
            OpalBase.Account.MosaicAttemptRecoveryPlanner.Plan
        )
        case broadcastApprovalRequired(
            OpalBase.Account.MosaicCommittedBroadcastCandidate
        )
        case resumeApprovedBroadcast(
            OpalBase.Account.MosaicCommittedBroadcastCandidate
        )
        case chainReconciliationRequired(OpalBase.Transaction.Hash)
    }

    enum Failure: Swift.Error, Sendable, Equatable {
        case recoveryInProgress
        case invalidJournal(
            OpalBase.Account.MosaicAttemptRecoveryPlanner.Error
        )
        case invalidSelectedInput
        case selectedInputMismatch
        case inputQuarantineFailed
        case invalidBroadcastCandidate
    }
}
#endif
