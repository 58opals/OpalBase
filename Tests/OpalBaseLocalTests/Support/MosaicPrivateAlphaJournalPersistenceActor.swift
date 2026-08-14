// MosaicPrivateAlphaJournalPersistenceActor.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) import OpalBase

actor MosaicPrivateAlphaJournalPersistenceActor {
    private var persistedEnvelope: Data?
    private var shouldCancelNextDeletion = false
    private var shouldFailNextDeletion = false

    init(persistedEnvelope: Data? = nil) {
        self.persistedEnvelope = persistedEnvelope.map(Data.init)
    }

    nonisolated func makePersistence(
        retaining lifetimeProbe:
            MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor? = nil
    )
        -> OpalBase.Account.MosaicPrivateAlphaJournal.Persistence {
        .init(
            loadEnvelope: {
                await lifetimeProbe?.recordAccess()
                return await self.loadEnvelope()
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
            compareAndDeleteEnvelopeDurably: { expected in
                await lifetimeProbe?.recordAccess()
                return try await self.compareAndDeleteEnvelopeDurably(
                    expected: expected
                )
            }
        )
    }

    func readPersistedEnvelope() -> Data? {
        persistedEnvelope.map(Data.init)
    }

    func replacePersistedEnvelope(_ replacement: Data) {
        persistedEnvelope = Data(replacement)
    }

    func scheduleCancellationForNextDeletion() {
        shouldCancelNextDeletion = true
    }

    func scheduleFailureForNextDeletion() {
        shouldFailNextDeletion = true
    }

    private func loadEnvelope() -> Data? {
        persistedEnvelope.map(Data.init)
    }

    private func createEnvelopeDurably(_ envelope: Data) -> Bool {
        guard persistedEnvelope == nil else { return false }
        persistedEnvelope = Data(envelope)
        return true
    }

    private func compareAndReplaceEnvelopeDurably(
        expected: Data,
        replacement: Data
    ) -> Bool {
        guard persistedEnvelope == expected else { return false }
        persistedEnvelope = Data(replacement)
        return true
    }

    private func compareAndDeleteEnvelopeDurably(
        expected: Data
    ) throws -> Bool {
        if shouldCancelNextDeletion {
            shouldCancelNextDeletion = false
            throw CancellationError()
        }
        if shouldFailNextDeletion {
            shouldFailNextDeletion = false
            throw CocoaError(.fileWriteUnknown)
        }
        guard persistedEnvelope == expected else { return false }
        persistedEnvelope = nil
        return true
    }
}
#endif
