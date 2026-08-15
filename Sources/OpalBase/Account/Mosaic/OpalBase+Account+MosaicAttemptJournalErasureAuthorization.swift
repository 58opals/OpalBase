// OpalBase+Account+MosaicAttemptJournalErasureAuthorization.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    /// Nonforgeable exact-snapshot proof for abandoned-fresh or terminal journal erasure.
    struct MosaicAttemptJournalErasureAuthorization: ~Copyable, Sendable {
        private let store: MosaicAttemptJournalStore
        private let expectedEnvelopeSHA256: Data

        init(
            store: MosaicAttemptJournalStore,
            expectedEnvelopeSHA256: Data
        ) {
            self.store = store
            self.expectedEnvelopeSHA256 = Data(expectedEnvelopeSHA256)
        }

        borrowing func authorizeJournalErasure() async throws
            -> MosaicAttemptJournalCleanupRequirement {
            try await store.authorizeJournalErasure(
                expectedEnvelopeSHA256: expectedEnvelopeSHA256
            )
        }
    }
}
#endif
