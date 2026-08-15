// OpalBase+Account+MosaicPrivateAlphaRecoveryOwner+Failure.swift

#if os(macOS)
extension _OpalBase.Account.MosaicPrivateAlphaRecoveryOwner {
    enum Failure: Swift.Error, Sendable, Equatable {
        case operationInProgress
        case invalidRecoveryState
        case invalidNetworkBinding
        case broadcastNotApproved
        case broadcastReconciliationRequired
        case walletStateMismatch
        case walletCleanupIncomplete
        case finalityNotAuthorized
        case terminalDispositionRequired
        case erasureAlreadyAuthorized
    }
}
#endif
