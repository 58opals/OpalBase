// OpalBase+Account+MosaicAttemptJournalErasureAuthorization.swift

#if os(macOS)

extension _OpalBase.Account {
    /// Nonforgeable origin proof for authorizing erasure of one abandoned fresh attempt.
    struct MosaicAttemptJournalErasureAuthorization: ~Copyable, Sendable {
        private let store: MosaicAttemptJournalStore

        init(store: MosaicAttemptJournalStore) {
            self.store = store
        }

        borrowing func authorizeJournalErasure() async throws
            -> MosaicAttemptJournalCleanupRequirement {
            try await store.authorizeJournalErasure()
        }
    }
}
#endif
