// OpalBase+Account+MosaicPrivateAlphaRuntime+ChainOutcome.swift

#if os(macOS)
extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Result of one exact, uncached chain reconciliation read.
    @_spi(MosaicPrivateAlpha)
    public enum ChainOutcome: Sendable, Equatable {
        case observed(ChainState)
        case heldUnknown(ChainPresenceUnknownReason)

        init(
            _ outcome: OpalBase.Account.MosaicPrivateAlphaRecoveryOwner
                .ChainOutcome
        ) {
            switch outcome {
            case let .observed(state):
                self = .observed(.init(state))
            case let .heldUnknown(reason):
                self = .heldUnknown(.init(reason))
            }
        }
    }
}
#endif
