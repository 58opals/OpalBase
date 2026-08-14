// OpalBase+Account+MosaicPrivateAlphaJournal+CleanupRequirement.swift

#if os(macOS)
extension OpalBase.Account.MosaicPrivateAlphaJournal {
    /// Opaque requirement derived from exact in-process or app-reported durable authorization.
    @_spi(MosaicPrivateAlpha)
    public struct CleanupRequirement: ~Copyable, Sendable {
        private let requirement:
            OpalBase.Account.MosaicAttemptJournalCleanupRequirement

        init(
            _ requirement: consuming
                OpalBase.Account.MosaicAttemptJournalCleanupRequirement
        ) {
            self.requirement = requirement
        }

        /// Immutable scope and envelope-digest binding that outer cleanup must match.
        @_spi(MosaicPrivateAlpha)
        public var context: CleanupContext {
            requirement.context
        }

        borrowing func confirmOuterCleanup(
            using confirmation: @Sendable (
                CleanupContext
            ) async throws -> Void
        ) async throws {
            try await requirement.confirmOuterCleanup(using: confirmation)
        }
    }
}
#endif
