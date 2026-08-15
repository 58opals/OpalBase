// OpalBase+Account+MosaicPrivateAlphaRuntime+ChainHoldReason.swift

#if os(macOS)
extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Chain regression that keeps terminal authority held for application policy review.
    @_spi(MosaicPrivateAlpha)
    public enum ChainHoldReason: Sendable, Equatable {
        case transactionDisappeared
        case blockIdentityChanged
        case confirmationDepthRetreated
    }
}
#endif
