// OpalBase+Account+MosaicPrivateAlphaJournal+LoadResult.swift

#if os(macOS)
extension OpalBase.Account.MosaicPrivateAlphaJournal {
    /// Opaque authenticated result for an existing journal at restart.
    @_spi(MosaicPrivateAlpha)
    public enum LoadResult: ~Copyable, Sendable {
        /// A nonempty attempt that requires wallet recovery execution.
        case loadedRecovery(LoadedRecovery)

        /// An authenticated empty attempt that may erase only its exact durable envelope.
        case abandonedFreshAttempt(AttemptDisposition)
    }
}
#endif
