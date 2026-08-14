// OpalBase+Account+MosaicAttemptJournalCleanupRequirement.swift

#if os(macOS)
extension _OpalBase.Account {
    /// Cleanup requirement derived from in-process authorization or app-reported durable authorization.
    struct MosaicAttemptJournalCleanupRequirement: ~Copyable, Sendable {
        let context: MosaicPrivateAlphaJournal.CleanupContext

        init(context: MosaicPrivateAlphaJournal.CleanupContext) {
            self.context = context
        }

        borrowing func confirmOuterCleanup(
            using confirmation: @Sendable (
                MosaicPrivateAlphaJournal.CleanupContext
            ) async throws -> Void
        ) async throws {
            try await confirmation(context)
        }
    }
}
#endif
