// OpalBase+Account+MosaicPrivateAlphaRecoveryOwner+ChainOutcome.swift

#if os(macOS)
extension _OpalBase.Account.MosaicPrivateAlphaRecoveryOwner {
    enum ChainOutcome: Sendable, Equatable {
        case observed(OpalBase.Account.MosaicAttemptChainState)
        case heldUnknown(
            OpalBase.Account.MosaicTransactionPresence.UnknownReason
        )
    }
}
#endif
