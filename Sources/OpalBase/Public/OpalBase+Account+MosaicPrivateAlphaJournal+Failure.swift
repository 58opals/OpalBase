// OpalBase+Account+MosaicPrivateAlphaJournal+Failure.swift

#if os(macOS)
extension OpalBase.Account.MosaicPrivateAlphaJournal {
    /// Redacted failure categories for app-owned private-alpha journal composition.
    @_spi(MosaicPrivateAlpha)
    public enum Failure: Swift.Error, Equatable, Sendable {
        case notFound
        case attemptAlreadyExists
        case persistenceUnavailable
        case stalePersistenceState
        case invalidJournalKey
        case journalVersionUnsupported
        case journalIntegrityFailed
        case journalCleanupRequired
        case outerCleanupIncomplete
        case journalOperationFailed

        init(_ failure: OpalBase.Account.MosaicAttemptJournalStore.Failure) {
            switch failure {
            case .notFound:
                self = .notFound
            case .alreadyExists:
                self = .attemptAlreadyExists
            case .creationUncertain:
                self = .journalOperationFailed
            case .loadFailed, .createFailed, .replaceFailed,
                 .erasureAuthorizationFailed:
                self = .persistenceUnavailable
            case .staleSnapshot:
                self = .stalePersistenceState
            case .cleanupRequired:
                self = .journalCleanupRequired
            case .erasureNotAuthorized, .journalErased:
                self = .journalOperationFailed
            case let .codec(codecFailure):
                switch codecFailure {
                case .invalidKeyMaterial:
                    self = .invalidJournalKey
                case .unsupportedVersion:
                    self = .journalVersionUnsupported
                case .malformedEnvelope, .authenticationFailed,
                     .decodingFailed, .invalidRecord, .invalidSnapshot:
                    self = .journalIntegrityFailed
                case .encodingFailed:
                    self = .journalOperationFailed
                }
            case .invalidJournal:
                self = .journalIntegrityFailed
            }
        }
    }
}
#endif
