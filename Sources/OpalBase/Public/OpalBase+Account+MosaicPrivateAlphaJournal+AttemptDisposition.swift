// OpalBase+Account+MosaicPrivateAlphaJournal+AttemptDisposition.swift

#if os(macOS)
extension OpalBase.Account.MosaicPrivateAlphaJournal {
    /// Opaque, nonforgeable proof that one exact fresh-attempt snapshot is eligible for erasure.
    @_spi(MosaicPrivateAlpha)
    public struct AttemptDisposition: ~Copyable, Sendable {
        private let authorization: OpalBase.Account.MosaicAttemptJournalErasureAuthorization

        init(
            _ authorization: consuming OpalBase.Account.MosaicAttemptJournalErasureAuthorization
        ) {
            self.authorization = authorization
        }

        borrowing func eraseJournal() async throws {
            try await authorization.eraseJournal()
        }
    }
}
#endif
