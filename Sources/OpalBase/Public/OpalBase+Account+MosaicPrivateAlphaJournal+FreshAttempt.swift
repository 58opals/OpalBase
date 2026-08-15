// OpalBase+Account+MosaicPrivateAlphaJournal+FreshAttempt.swift

#if os(macOS)
extension OpalBase.Account.MosaicPrivateAlphaJournal {
    /// Opaque one-use proof that an empty attempt journal was exclusively and durably created.
    @_spi(MosaicPrivateAlpha)
    public struct FreshAttempt: ~Copyable, Sendable {
        let attempt: OpalBase.Account.MosaicAttemptJournalStore.FreshAttempt

        init(
            _ attempt: consuming OpalBase.Account.MosaicAttemptJournalStore.FreshAttempt
        ) {
            self.attempt = attempt
        }

        consuming func authorizeAbandonment() async throws
            -> OpalBase.Account.MosaicAttemptJournalErasureAuthorization {
            try await attempt.authorizeAbandonment()
        }

        consuming func claimAttempt()
            -> OpalBase.Account.MosaicAttemptJournalStore.FreshAttempt {
            consume attempt
        }
    }
}
#endif
