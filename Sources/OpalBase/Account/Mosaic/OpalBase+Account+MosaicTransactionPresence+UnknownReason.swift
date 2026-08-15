// OpalBase+Account+MosaicTransactionPresence+UnknownReason.swift

#if os(macOS)
extension _OpalBase.Account.MosaicTransactionPresence {
    enum UnknownReason: Sendable, Equatable {
        case unavailable
        case exactTransactionMismatch
        case invalidChainMetadata
    }
}
#endif
