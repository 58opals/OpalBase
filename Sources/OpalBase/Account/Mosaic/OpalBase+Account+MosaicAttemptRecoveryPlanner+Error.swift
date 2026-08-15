// OpalBase+Account+MosaicAttemptRecoveryPlanner+Error.swift

#if os(macOS)
extension _OpalBase.Account.MosaicAttemptRecoveryPlanner {
    enum Error: Swift.Error, Sendable, Equatable {
        case invalidFirstRecord
        case invalidRecord
        case attemptBindingMismatch
        case reservationReferenceMismatch
        case invalidTransition
        case conflictingTransaction
        case transactionHashMismatch
        case unsupportedPrivateAlphaProfile
    }
}
#endif
