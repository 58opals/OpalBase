// AccountMosaicPrivateAlphaJournalValidator.swift

#if os(macOS)
import CryptoKit
import Foundation
import Testing
@_spi(MosaicPrivateAlpha) import OpalBase

@Suite("OpalBase.Account private-alpha Mosaic journal", .tags(.unit, .wallet))
struct AccountMosaicPrivateAlphaJournalValidator {
    private typealias Journal = OpalBase.Account.MosaicPrivateAlphaJournal

    @Test("Erase only the exact abandoned fresh attempt")
    func eraseOnlyExactAbandonedFreshAttempt() async throws {
        let persistenceActor = MosaicPrivateAlphaJournalPersistenceActor()
        let freshAttempt = try await Journal.createFreshAttempt(
            fieldDerivedJournalKey: makeFieldDerivedJournalKey(),
            scope: makeScope(),
            persistence: persistenceActor.makePersistence()
        )
        #expect(await persistenceActor.readPersistedEnvelope() != nil)

        let disposition = try await Journal.abandonFreshAttempt(freshAttempt)
        try await Journal.eraseJournal(authorizedBy: disposition)
        #expect(await persistenceActor.readPersistedEnvelope() == nil)

        try await Journal.eraseJournal(authorizedBy: disposition)
        #expect(await persistenceActor.readPersistedEnvelope() == nil)
    }

    @Test("Preserve a replacement when abandoned-attempt erasure is stale")
    func preserveReplacementWhenErasureIsStale() async throws {
        let persistenceActor = MosaicPrivateAlphaJournalPersistenceActor()
        let freshAttempt = try await Journal.createFreshAttempt(
            fieldDerivedJournalKey: makeFieldDerivedJournalKey(),
            scope: makeScope(),
            persistence: persistenceActor.makePersistence()
        )
        let originalEnvelope = try #require(
            await persistenceActor.readPersistedEnvelope()
        )
        let disposition = try await Journal.abandonFreshAttempt(freshAttempt)
        var replacementEnvelope = originalEnvelope
        replacementEnvelope.append(0x81)
        await persistenceActor.replacePersistedEnvelope(replacementEnvelope)

        do {
            try await Journal.eraseJournal(authorizedBy: disposition)
            Issue.record("Expected exact-envelope erasure to reject a replacement")
        } catch let failure as Journal.Failure {
            #expect(failure == .stalePersistenceState)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }
        #expect(
            await persistenceActor.readPersistedEnvelope()
                == replacementEnvelope
        )
    }

    @Test("Retain persistence for erasure retries and release it after success")
    func retainPersistenceForRetriesAndReleaseAfterErasure() async throws {
        let persistenceActor = MosaicPrivateAlphaJournalPersistenceActor()
        let originalEnvelope: Data
        let disposition: Journal.AttemptDisposition
        weak var lifetimeProbe:
            MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor?
        do {
            let strongLifetimeProbe =
                MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor()
            lifetimeProbe = strongLifetimeProbe
            let freshAttempt = try await Journal.createFreshAttempt(
                fieldDerivedJournalKey: makeFieldDerivedJournalKey(),
                scope: makeScope(),
                persistence: persistenceActor.makePersistence(
                    retaining: strongLifetimeProbe
                )
            )
            originalEnvelope = try #require(
                await persistenceActor.readPersistedEnvelope()
            )
            disposition = try await Journal.abandonFreshAttempt(freshAttempt)
            #expect(await strongLifetimeProbe.readAccessCount() == 1)
        }
        #expect(lifetimeProbe != nil)
        await persistenceActor.scheduleFailureForNextDeletion()

        do {
            try await Journal.eraseJournal(authorizedBy: disposition)
            Issue.record("Expected a mapped persistence failure")
        } catch let failure as Journal.Failure {
            #expect(failure == .persistenceUnavailable)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }
        #expect(
            await persistenceActor.readPersistedEnvelope()
                == originalEnvelope
        )
        #expect(lifetimeProbe != nil)

        await persistenceActor.scheduleCancellationForNextDeletion()

        do {
            try await Journal.eraseJournal(authorizedBy: disposition)
            Issue.record("Expected deletion cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected CancellationError to remain unmapped")
        }
        #expect(
            await persistenceActor.readPersistedEnvelope()
                == originalEnvelope
        )
        #expect(lifetimeProbe != nil)

        try await Journal.eraseJournal(authorizedBy: disposition)
        #expect(await persistenceActor.readPersistedEnvelope() == nil)
        #expect(lifetimeProbe == nil)
    }

    private func makeFieldDerivedJournalKey(
        byte: UInt8 = 0x5c,
        byteCount: Int = 32
    ) -> SymmetricKey {
        SymmetricKey(data: Data(repeating: byte, count: byteCount))
    }

    private func makeScope(
        journalIdentifierLastByte: UInt8 = 0x01
    ) -> Journal.Scope {
        let walletIdentifier = UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0x01, 0x01
            )
        )
        let journalIdentifier = UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, journalIdentifierLastByte
            )
        )
        return .init(
            walletIdentifier: walletIdentifier,
            journalIdentifier: journalIdentifier
        )
    }
}
#endif
