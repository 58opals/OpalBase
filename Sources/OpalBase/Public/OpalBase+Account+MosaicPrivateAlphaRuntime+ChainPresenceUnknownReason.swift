// OpalBase+Account+MosaicPrivateAlphaRuntime+ChainPresenceUnknownReason.swift

#if os(macOS)
extension OpalBase.Account.MosaicPrivateAlphaRuntime {
    /// Fail-closed reason that exact chain presence could not be established.
    @_spi(MosaicPrivateAlpha)
    public enum ChainPresenceUnknownReason: Sendable, Equatable {
        case unavailable
        case exactTransactionMismatch
        case invalidChainMetadata

        init(_ reason: OpalBase.Account.MosaicTransactionPresence.UnknownReason) {
            switch reason {
            case .unavailable:
                self = .unavailable
            case .exactTransactionMismatch:
                self = .exactTransactionMismatch
            case .invalidChainMetadata:
                self = .invalidChainMetadata
            }
        }
    }
}
#endif
