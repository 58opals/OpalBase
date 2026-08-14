// OpalBase+Account+MosaicAttemptJournalErasureAuthorization.swift

#if os(macOS)
import Foundation

extension _OpalBase.Account {
    /// Nonforgeable origin proof for deleting the exact empty snapshot of an abandoned fresh attempt.
    struct MosaicAttemptJournalErasureAuthorization: ~Copyable, Sendable {
        private let store: MosaicAttemptJournalStore
        private let expectedEnvelope: Data

        init(
            store: MosaicAttemptJournalStore,
            expectedEnvelope: Data
        ) {
            self.store = store
            self.expectedEnvelope = Data(expectedEnvelope)
        }

        borrowing func eraseJournal() async throws {
            try await store.eraseJournal(matching: expectedEnvelope)
        }
    }
}
#endif
