// OpalBase+Account+MosaicPrivateAlphaJournal+PersistedState.swift

#if os(macOS)
import Foundation

extension OpalBase.Account.MosaicPrivateAlphaJournal {
    /// App-owned durable state for one private-alpha journal scope.
    @_spi(MosaicPrivateAlpha)
    public enum PersistedState: Equatable, Sendable {
        /// No active envelope or pending journal-erasure authorization exists.
        case absent

        /// The exact encrypted envelope that remains authoritative for recovery.
        case encryptedEnvelope(Data)

        /// Exact-envelope terminal erasure was durably authorized, but outer cleanup is not yet proven.
        ///
        /// This state must be reported only after the persistence implementation atomically compares the
        /// authoritative envelope and commits the scope-bound authorization marker. It is not evidence
        /// that ciphertext, key material, or other private attempt artifacts have been removed.
        case journalErasureAuthorized(CleanupContext)
    }
}
#endif
