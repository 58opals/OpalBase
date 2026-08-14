// OpalBase+Account+MosaicPrivateAlphaJournal+AttemptDisposition.swift

#if os(macOS)
extension OpalBase.Account.MosaicPrivateAlphaJournal {
    /// Opaque, nonforgeable proof that one fresh attempt is eligible for exact erasure authorization.
    @_spi(MosaicPrivateAlpha)
    public struct AttemptDisposition: ~Copyable, Sendable {
        private let authorization: OpalBase.Account.MosaicAttemptJournalErasureAuthorization

        init(
            _ authorization: consuming OpalBase.Account.MosaicAttemptJournalErasureAuthorization
        ) {
            self.authorization = authorization
        }

        borrowing func authorizeJournalErasure() async throws
            -> OpalBase.Account.MosaicAttemptJournalCleanupRequirement {
            try await authorization.authorizeJournalErasure()
        }
    }
}
#endif
