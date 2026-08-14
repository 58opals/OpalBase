// OpalBase+Account+MosaicPrivateAlphaJournal+Persistence.swift

#if os(macOS)
import Foundation

extension OpalBase.Account.MosaicPrivateAlphaJournal {
    /// App-owned durable operations for one opaque encrypted Mosaic journal envelope.
    @_spi(MosaicPrivateAlpha)
    public struct Persistence: Sendable {
        let journalPersistence: OpalBase.Account.MosaicAttemptJournalStore.Persistence

        /// Creates persistence operations with exact replacement and terminal-erasure authorization.
        ///
        /// `loadJournalState` must report a durable erasure authorization instead of its retained envelope.
        /// Creation must reject both an existing envelope and an erasure authorization. Replacement and
        /// authorization must compare every byte of the expected envelope atomically. Authorization must
        /// verify that its context contains the matching envelope SHA-256 and durably install that context as
        /// the terminal marker without claiming that outer ciphertext or key material was removed. The exact
        /// same expected envelope and context must return `true` idempotently when already authorized,
        /// including after commit-then-throw or commit-then-cancel. A different envelope or context returns
        /// `false` without mutation. Creation and replacement must fail while the marker exists. A thrown
        /// authorization is outcome-uncertain and must be resolved by exact retry or state read-back. Every
        /// successful mutation must be durable before returning. The closures must not log or otherwise
        /// disclose envelope bytes or cleanup context.
        @_spi(MosaicPrivateAlpha)
        public init(
            loadJournalState: @escaping @Sendable () async throws
                -> PersistedState,
            createEnvelopeDurably: @escaping @Sendable (Data) async throws -> Bool,
            compareAndReplaceEnvelopeDurably: @escaping @Sendable (
                _ expected: Data,
                _ replacement: Data
            ) async throws -> Bool,
            compareAndAuthorizeJournalErasureDurably: @escaping @Sendable (
                _ expectedEnvelope: Data,
                _ context: CleanupContext
            ) async throws -> Bool
        ) {
            journalPersistence = .init(
                loadState: loadJournalState,
                createDurably: createEnvelopeDurably,
                compareAndReplaceDurably: compareAndReplaceEnvelopeDurably,
                compareAndAuthorizeErasureDurably:
                    compareAndAuthorizeJournalErasureDurably
            )
        }
    }
}
#endif
