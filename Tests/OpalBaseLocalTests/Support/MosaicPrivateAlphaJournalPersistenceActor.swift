// MosaicPrivateAlphaJournalPersistenceActor.swift

#if os(macOS)
import CryptoKit
import Foundation
@_spi(MosaicPrivateAlpha) import OpalBase

actor MosaicPrivateAlphaJournalPersistenceActor {
    private var persistedEnvelope: Data?
    private var erasureAuthorizationContext:
        OpalBase.Account.MosaicPrivateAlphaJournal.CleanupContext?
    private var retainsOuterKeyMaterial: Bool
    private var shouldCancelNextAuthorization = false
    private var shouldFailNextAuthorization = false
    private var shouldCommitThenCancelNextAuthorization = false
    private var shouldCommitThenFailNextAuthorization = false
    private var shouldCancelNextCleanup = false
    private var shouldFailNextCleanup = false

    init(persistedEnvelope: Data? = nil) {
        self.persistedEnvelope = persistedEnvelope.map { Data($0) }
        retainsOuterKeyMaterial = persistedEnvelope != nil
    }

    nonisolated func makePersistence(
        retaining lifetimeProbe:
            MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor? = nil
    )
        -> OpalBase.Account.MosaicPrivateAlphaJournal.Persistence {
        .init(
            loadJournalState: {
                await lifetimeProbe?.recordAccess()
                return await self.loadJournalState()
            },
            createEnvelopeDurably: { envelope in
                await lifetimeProbe?.recordAccess()
                return await self.createEnvelopeDurably(envelope)
            },
            compareAndReplaceEnvelopeDurably: { expected, replacement in
                await lifetimeProbe?.recordAccess()
                return await self.compareAndReplaceEnvelopeDurably(
                    expected: expected,
                    replacement: replacement
                )
            },
            compareAndAuthorizeJournalErasureDurably: { expected, context in
                await lifetimeProbe?.recordAccess()
                return try await self
                    .compareAndAuthorizeJournalErasureDurably(
                        expected: expected,
                        context: context
                    )
            }
        )
    }

    func readJournalState()
        -> OpalBase.Account.MosaicPrivateAlphaJournal.PersistedState {
        loadJournalState()
    }

    func readPersistedEnvelope() -> Data? {
        persistedEnvelope.map { Data($0) }
    }

    var hasRetainedOuterKeyMaterial: Bool {
        retainsOuterKeyMaterial
    }

    func replacePersistedEnvelope(_ replacement: Data) {
        persistedEnvelope = Data(replacement)
        erasureAuthorizationContext = nil
        retainsOuterKeyMaterial = true
    }

    func scheduleCancellationForNextAuthorization() {
        shouldCancelNextAuthorization = true
    }

    func scheduleFailureForNextAuthorization() {
        shouldFailNextAuthorization = true
    }

    func scheduleCommitThenCancellationForNextAuthorization() {
        shouldCommitThenCancelNextAuthorization = true
    }

    func scheduleCommitThenFailureForNextAuthorization() {
        shouldCommitThenFailNextAuthorization = true
    }

    func scheduleCancellationForNextCleanup() {
        shouldCancelNextCleanup = true
    }

    func scheduleFailureForNextCleanup() {
        shouldFailNextCleanup = true
    }

    func removeOuterMaterialAndConfirmCleanup(
        matching context:
            OpalBase.Account.MosaicPrivateAlphaJournal.CleanupContext
    ) throws {
        if shouldCancelNextCleanup {
            shouldCancelNextCleanup = false
            throw CancellationError()
        }
        if shouldFailNextCleanup {
            shouldFailNextCleanup = false
            throw CocoaError(.fileWriteUnknown)
        }
        guard erasureAuthorizationContext == context,
              let persistedEnvelope,
              context.expectedEnvelopeSHA256
                == Data(SHA256.hash(data: persistedEnvelope)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.persistedEnvelope = nil
        retainsOuterKeyMaterial = false
        erasureAuthorizationContext = nil
    }

    private func loadJournalState()
        -> OpalBase.Account.MosaicPrivateAlphaJournal.PersistedState {
        if let erasureAuthorizationContext {
            return .journalErasureAuthorized(erasureAuthorizationContext)
        }
        guard let persistedEnvelope else {
            return .absent
        }
        return .encryptedEnvelope(Data(persistedEnvelope))
    }

    private func createEnvelopeDurably(_ envelope: Data) -> Bool {
        guard persistedEnvelope == nil,
              erasureAuthorizationContext == nil else {
            return false
        }
        persistedEnvelope = Data(envelope)
        retainsOuterKeyMaterial = true
        return true
    }

    private func compareAndReplaceEnvelopeDurably(
        expected: Data,
        replacement: Data
    ) -> Bool {
        guard erasureAuthorizationContext == nil,
              persistedEnvelope == expected else {
            return false
        }
        persistedEnvelope = Data(replacement)
        return true
    }

    private func compareAndAuthorizeJournalErasureDurably(
        expected: Data,
        context: OpalBase.Account.MosaicPrivateAlphaJournal.CleanupContext
    ) throws -> Bool {
        let expectedEnvelopeSHA256 = Data(SHA256.hash(data: expected))
        guard context.expectedEnvelopeSHA256 == expectedEnvelopeSHA256 else {
            return false
        }
        if let erasureAuthorizationContext {
            return erasureAuthorizationContext == context
        }
        if shouldCancelNextAuthorization {
            shouldCancelNextAuthorization = false
            throw CancellationError()
        }
        if shouldFailNextAuthorization {
            shouldFailNextAuthorization = false
            throw CocoaError(.fileWriteUnknown)
        }
        guard persistedEnvelope == expected else { return false }
        erasureAuthorizationContext = context
        if shouldCommitThenCancelNextAuthorization {
            shouldCommitThenCancelNextAuthorization = false
            throw CancellationError()
        }
        if shouldCommitThenFailNextAuthorization {
            shouldCommitThenFailNextAuthorization = false
            throw CocoaError(.fileWriteUnknown)
        }
        return true
    }
}
#endif
