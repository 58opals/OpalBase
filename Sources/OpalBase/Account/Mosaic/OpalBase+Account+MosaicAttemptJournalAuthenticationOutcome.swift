// OpalBase+Account+MosaicAttemptJournalAuthenticationOutcome.swift

#if os(macOS)
extension _OpalBase.Account {
    /// Exclusive authenticated restart authority for one existing Mosaic attempt journal.
    enum MosaicAttemptJournalAuthenticationOutcome: ~Copyable, Sendable {
        case abandonedFreshAttempt(MosaicAttemptJournalErasureAuthorization)
        case loadedRecovery(MosaicAttemptJournalStore.LoadedRecovery)
    }
}
#endif
