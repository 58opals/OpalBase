// AccountMosaicPrivateAlphaJournalValidator.swift

#if os(macOS)
import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) import OpalBase

@Suite("OpalBase.Account private-alpha Mosaic journal", .tags(.unit, .wallet))
struct AccountMosaicPrivateAlphaJournalValidator {
    private typealias Journal = OpalBase.Account.MosaicPrivateAlphaJournal

    @Test("Require outer cleanup after exact erasure authorization")
    func requireOuterCleanupAfterExactErasureAuthorization() async throws {
        let persistenceActor = MosaicPrivateAlphaJournalPersistenceActor()
        let scope = makeScope()
        let freshAttempt = try await Journal.createFreshAttempt(
            fieldDerivedJournalKey: makeFieldDerivedJournalKey(),
            scope: scope,
            persistence: persistenceActor.makePersistence()
        )
        let envelope = try #require(
            await persistenceActor.readPersistedEnvelope()
        )
        let expectedContext = try #require(
            Journal.CleanupContext(
                scope: scope,
                expectedEnvelopeSHA256: OpalCrypto.Hashing.sha256(envelope)
            )
        )

        let disposition = try await Journal.abandonFreshAttempt(freshAttempt)
        let cleanupRequirement = try await Journal.authorizeJournalErasure(
            authorizedBy: disposition
        )
        #expect(await persistenceActor.readPersistedEnvelope() == envelope)
        #expect(await persistenceActor.hasRetainedOuterKeyMaterial)
        #expect(cleanupRequirement.context == expectedContext)
        #expect(
            await persistenceActor.readJournalState()
                == .journalErasureAuthorized(expectedContext)
        )

        do {
            _ = try await Journal.loadAuthorizedJournalCleanup(
                scope: makeScope(journalIdentifierLastByte: 0x02),
                persistence: persistenceActor.makePersistence()
            )
            Issue.record("Expected cleanup authority to reject another scope")
        } catch let failure as Journal.Failure {
            #expect(failure == .stalePersistenceState)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }

        do {
            _ = try await Journal.createFreshAttempt(
                fieldDerivedJournalKey: makeFieldDerivedJournalKey(),
                scope: scope,
                persistence: persistenceActor.makePersistence()
            )
            Issue.record("Expected terminal authorization to block recreation")
        } catch let failure as Journal.Failure {
            #expect(failure == .attemptAlreadyExists)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }

        try await Journal.completeJournalErasure(
            requiredBy: cleanupRequirement,
            confirmOuterCleanup: { context in
                try await persistenceActor
                    .removeOuterMaterialAndConfirmCleanup(matching: context)
            }
        )
        #expect(await persistenceActor.readPersistedEnvelope() == nil)
        #expect(!(await persistenceActor.hasRetainedOuterKeyMaterial))
        #expect(await persistenceActor.readJournalState() == .absent)
    }

    @Test("Preserve a replacement when erasure authorization is stale")
    func preserveReplacementWhenErasureAuthorizationIsStale() async throws {
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
            _ = try await Journal.authorizeJournalErasure(
                authorizedBy: disposition
            )
            Issue.record("Expected exact authorization to reject a replacement")
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

    private func makeFieldDerivedJournalKey(
        byte: UInt8 = 0x5c
    ) -> Journal.JournalKey {
        try! .init(
            fieldDerivedKeyMaterial: Data(repeating: byte, count: 32)
        )
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
