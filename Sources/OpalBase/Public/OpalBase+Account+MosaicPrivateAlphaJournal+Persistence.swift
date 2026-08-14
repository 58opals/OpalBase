// OpalBase+Account+MosaicPrivateAlphaJournal+Persistence.swift

#if os(macOS)
import Foundation

extension OpalBase.Account.MosaicPrivateAlphaJournal {
    /// App-owned durable operations for one opaque encrypted Mosaic journal envelope.
    @_spi(MosaicPrivateAlpha)
    public struct Persistence: Sendable {
        let journalPersistence: OpalBase.Account.MosaicAttemptJournalStore.Persistence

        /// Creates persistence operations with exact compare-and-swap replacement and deletion.
        ///
        /// Creation must not replace an existing value. Replacement and deletion must compare every byte
        /// of the expected envelope atomically. A mismatch returns `false` without mutation. A thrown
        /// operation must leave the prior value authoritative. Every successful mutation must be durable
        /// before returning. The closures must not log or otherwise disclose envelope bytes.
        @_spi(MosaicPrivateAlpha)
        public init(
            loadEnvelope: @escaping @Sendable () async throws -> Data?,
            createEnvelopeDurably: @escaping @Sendable (Data) async throws -> Bool,
            compareAndReplaceEnvelopeDurably: @escaping @Sendable (
                _ expected: Data,
                _ replacement: Data
            ) async throws -> Bool,
            compareAndDeleteEnvelopeDurably: @escaping @Sendable (
                _ expected: Data
            ) async throws -> Bool
        ) {
            journalPersistence = .init(
                load: loadEnvelope,
                createDurably: createEnvelopeDurably,
                compareAndReplaceDurably: compareAndReplaceEnvelopeDurably,
                compareAndDeleteDurably: compareAndDeleteEnvelopeDurably
            )
        }
    }
}
#endif
