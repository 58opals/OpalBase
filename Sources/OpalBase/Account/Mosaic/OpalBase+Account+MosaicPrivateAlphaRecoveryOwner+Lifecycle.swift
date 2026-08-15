// OpalBase+Account+MosaicPrivateAlphaRecoveryOwner+Lifecycle.swift

#if os(macOS)
extension _OpalBase.Account.MosaicPrivateAlphaRecoveryOwner {
    enum Lifecycle: Equatable {
        case ready
        case performing
        case terminal
        case erasureAuthorizing
        case erasureAuthorized
    }
}
#endif
