// OpalBase+Account+MosaicPrivateAlphaRuntime+Outcome.swift

#if os(macOS)
import Foundation

extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Redacted next concrete recovery boundary for the exact authenticated attempt.
    @_spi(MosaicPrivateAlpha)
    public enum Outcome: Sendable, Equatable {
        case walletReconciliationHeld
        case locallySignedContinuation(transactionBytes: Data)
        case broadcastApprovalRequired
        case resumeApprovedBroadcast
        case broadcastReconciliationHeld
        case chainReconciliationRequired(ChainState)
        case terminal(TerminalDisposition)

        init(_ outcome: OpalBase.Account.MosaicPrivateAlphaRecoveryOwner.Outcome) {
            switch outcome {
            case .walletReconciliationHeld:
                self = .walletReconciliationHeld
            case let .locallySignedContinuation(_, transaction):
                self = .locallySignedContinuation(
                    transactionBytes: Data(
                        transaction.signedFusionTransactionBytes
                    )
                )
            case .broadcastApprovalRequired:
                self = .broadcastApprovalRequired
            case .resumeApprovedBroadcast:
                self = .resumeApprovedBroadcast
            case .broadcastReconciliationHeld:
                self = .broadcastReconciliationHeld
            case let .chainReconciliationRequired(state):
                self = .chainReconciliationRequired(.init(state))
            case let .terminal(disposition):
                self = .terminal(.init(disposition))
            }
        }
    }
}
#endif
