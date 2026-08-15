// OpalBase+Account+MosaicAttemptChainState+HoldReason.swift

#if os(macOS)
extension _OpalBase.Account.MosaicAttemptChainState {
    enum HoldReason: Sendable, Equatable {
        case transactionDisappeared
        case blockIdentityChanged
        case confirmationDepthRetreated
    }
}
#endif
