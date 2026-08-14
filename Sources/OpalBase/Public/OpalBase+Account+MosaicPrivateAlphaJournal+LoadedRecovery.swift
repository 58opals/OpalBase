// OpalBase+Account+MosaicPrivateAlphaJournal+LoadedRecovery.swift

#if os(macOS)
extension OpalBase.Account.MosaicPrivateAlphaJournal {
    /// Opaque one-use proof of a nonempty, authenticated, structurally valid recovery journal.
    @_spi(MosaicPrivateAlpha)
    public struct LoadedRecovery: ~Copyable, Sendable {
        let recovery: OpalBase.Account.MosaicAttemptJournalStore.LoadedRecovery

        init(
            _ recovery: consuming OpalBase.Account.MosaicAttemptJournalStore.LoadedRecovery
        ) {
            self.recovery = recovery
        }
    }
}
#endif
