// OpalBase+Account+MosaicPrivateAlphaRuntime+Failure.swift

#if os(macOS)
extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Redacted private-alpha runtime failure categories.
    @_spi(MosaicPrivateAlpha)
    public enum Failure: Swift.Error, Sendable, Equatable {
        case invalidBinding
        case invalidNetworkBinding
        case invalidRecoveryState
        case oneTimeCapabilityAlreadyClaimed
        case operationInProgress
        case walletStateMismatch
        case walletCleanupIncomplete
        case broadcastUnavailable
        case broadcastNotApproved
        case broadcastReconciliationRequired
        case finalityNotAuthorized
        case terminalDispositionRequired
        case erasureAlreadyAuthorized
        case journalPersistenceUnavailable
        case invalidTransaction
        case runtimeOperationFailed

        init(_ error: any Swift.Error) {
            switch error {
            case let failure as OpalBase.Account
                .MosaicPrivateAlphaRecoveryOwner.Failure:
                switch failure {
                case .operationInProgress:
                    self = .operationInProgress
                case .invalidRecoveryState:
                    self = .invalidRecoveryState
                case .invalidNetworkBinding:
                    self = .invalidNetworkBinding
                case .broadcastNotApproved:
                    self = .broadcastNotApproved
                case .broadcastReconciliationRequired:
                    self = .broadcastReconciliationRequired
                case .walletStateMismatch:
                    self = .walletStateMismatch
                case .walletCleanupIncomplete:
                    self = .walletCleanupIncomplete
                case .finalityNotAuthorized:
                    self = .finalityNotAuthorized
                case .terminalDispositionRequired:
                    self = .terminalDispositionRequired
                case .erasureAlreadyAuthorized:
                    self = .erasureAlreadyAuthorized
                }
            case is OpalBase.WalletSecurityProfile.Error:
                self = .broadcastUnavailable
            case let failure as OpalBase.Account.MosaicHostFailure:
                switch failure {
                case .invalidNetworkBinding,
                     .invalidProfileNetworkBinding,
                     .invalidReservationProfile:
                    self = .invalidNetworkBinding
                case .journalPersistenceFailed:
                    self = .journalPersistenceUnavailable
                case .broadcastNotApproved:
                    self = .broadcastNotApproved
                case .reconciliationRequired:
                    self = .broadcastReconciliationRequired
                case .invalidCompleteTransaction:
                    self = .invalidTransaction
                default:
                    self = .runtimeOperationFailed
                }
            case is OpalBase.Account.MosaicAttemptJournalStore.Failure:
                self = .journalPersistenceUnavailable
            default:
                self = .runtimeOperationFailed
            }
        }
    }
}
#endif
