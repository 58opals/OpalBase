// AccountMosaicPrivateAlphaJournalCreationRecoveryValidator.swift

#if os(macOS)
import CryptoKit
import Foundation
import Testing
@_spi(MosaicPrivateAlpha) import OpalBase

@Suite(
    "OpalBase.Account private-alpha Mosaic journal creation recovery",
    .tags(.unit, .wallet)
)
struct AccountMosaicPrivateAlphaJournalCreationRecoveryValidator {
    private typealias Journal = OpalBase.Account.MosaicPrivateAlphaJournal

    @Test("Recover an authenticated empty journal as retryable erasure authority")
    func recoverAuthenticatedEmptyJournalForErasure() async throws {
        let fixture = try await makeRestartedEmptyJournal()
        let loadResult = try await Journal.loadAuthenticatedRecovery(
            fieldDerivedJournalKey: fixture.fieldDerivedJournalKey,
            scope: fixture.scope,
            persistence: fixture.persistenceActor.makePersistence()
        )

        switch consume loadResult {
        case let .abandonedFreshAttempt(disposition):
            await fixture.persistenceActor
                .scheduleCancellationForNextAuthorization()
            do {
                _ = try await Journal.authorizeJournalErasure(
                    authorizedBy: disposition
                )
                Issue.record("Expected recovered authorization cancellation")
            } catch is CancellationError {
            } catch {
                Issue.record("Expected CancellationError to remain unmapped")
            }
            #expect(
                await fixture.persistenceActor.readPersistedEnvelope()
                    == fixture.envelope
            )

            let cleanupRequirement = try await Journal
                .authorizeJournalErasure(authorizedBy: disposition)
            #expect(
                await fixture.persistenceActor.readPersistedEnvelope()
                    == fixture.envelope
            )

            try await Journal.completeJournalErasure(
                requiredBy: cleanupRequirement,
                confirmOuterCleanup: { context in
                    try await fixture.persistenceActor
                        .removeOuterMaterialAndConfirmCleanup(matching: context)
                }
            )
            #expect(
                await fixture.persistenceActor.readPersistedEnvelope() == nil
            )
        case .loadedRecovery:
            Issue.record("Expected authenticated empty-journal erasure authority")
        }
    }

    @Test("Preserve replacement bytes from recovered erasure authorization")
    func preserveReplacementWhenRecoveredAuthorizationIsStale() async throws {
        let fixture = try await makeRestartedEmptyJournal()
        let loadResult = try await Journal.loadAuthenticatedRecovery(
            fieldDerivedJournalKey: fixture.fieldDerivedJournalKey,
            scope: fixture.scope,
            persistence: fixture.persistenceActor.makePersistence()
        )
        var replacementEnvelope = fixture.envelope
        replacementEnvelope.append(0x91)
        await fixture.persistenceActor
            .replacePersistedEnvelope(replacementEnvelope)

        switch consume loadResult {
        case let .abandonedFreshAttempt(disposition):
            do {
                _ = try await Journal.authorizeJournalErasure(
                    authorizedBy: disposition
                )
                Issue.record("Expected authorization to reject replacement bytes")
            } catch let failure as Journal.Failure {
                #expect(failure == .stalePersistenceState)
            } catch {
                Issue.record("Expected a mapped journal failure")
            }
            #expect(
                await fixture.persistenceActor.readPersistedEnvelope()
                    == replacementEnvelope
            )
        case .loadedRecovery:
            Issue.record("Expected authenticated empty-journal erasure authority")
        }
    }

    @Test("Resume authorized outer cleanup without reconstructing the journal key")
    func resumeAuthorizedOuterCleanupWithoutJournalKey() async throws {
        let fixture = try await makeRestartedEmptyJournal()
        let loadResult = try await Journal.loadAuthenticatedRecovery(
            fieldDerivedJournalKey: fixture.fieldDerivedJournalKey,
            scope: fixture.scope,
            persistence: fixture.persistenceActor.makePersistence()
        )
        switch consume loadResult {
        case let .abandonedFreshAttempt(disposition):
            _ = try await Journal.authorizeJournalErasure(
                authorizedBy: disposition
            )
        case .loadedRecovery:
            Issue.record("Expected authenticated empty-journal authority")
            return
        }

        do {
            _ = try await Journal.loadAuthenticatedRecovery(
                fieldDerivedJournalKey: fixture.fieldDerivedJournalKey,
                scope: fixture.scope,
                persistence: fixture.persistenceActor.makePersistence()
            )
            Issue.record("Expected active recovery to reject terminal authorization")
        } catch let failure as Journal.Failure {
            #expect(failure == .journalCleanupRequired)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }

        guard let cleanupRequirement = try await Journal
            .loadAuthorizedJournalCleanup(
                scope: fixture.scope,
                persistence: fixture.persistenceActor.makePersistence()
            ) else {
            Issue.record("Expected durable cleanup authority after restart")
            return
        }
        await fixture.persistenceActor.scheduleFailureForNextCleanup()
        do {
            try await Journal.completeJournalErasure(
                requiredBy: cleanupRequirement,
                confirmOuterCleanup: { context in
                    try await fixture.persistenceActor
                        .removeOuterMaterialAndConfirmCleanup(matching: context)
                }
            )
            Issue.record("Expected incomplete outer cleanup")
        } catch let failure as Journal.Failure {
            #expect(failure == .outerCleanupIncomplete)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }
        #expect(
            await fixture.persistenceActor.readPersistedEnvelope()
                == fixture.envelope
        )

        try await Journal.completeJournalErasure(
            requiredBy: cleanupRequirement,
            confirmOuterCleanup: { context in
                try await fixture.persistenceActor
                    .removeOuterMaterialAndConfirmCleanup(matching: context)
            }
        )
        #expect(await fixture.persistenceActor.readPersistedEnvelope() == nil)
        #expect(!(await fixture.persistenceActor.hasRetainedOuterKeyMaterial))
    }

    private func makeRestartedEmptyJournal() async throws -> (
        persistenceActor: MosaicPrivateAlphaJournalPersistenceActor,
        fieldDerivedJournalKey: SymmetricKey,
        scope: Journal.Scope,
        envelope: Data
    ) {
        let originalPersistenceActor = MosaicPrivateAlphaJournalPersistenceActor()
        let fieldDerivedJournalKey = SymmetricKey(
            data: Data(repeating: 0x73, count: 32)
        )
        let scope = Journal.Scope(
            walletIdentifier: UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0x02, 0x01
                )
            ),
            journalIdentifier: UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0x02, 0x02
                )
            )
        )
        _ = try await Journal.createFreshAttempt(
            fieldDerivedJournalKey: fieldDerivedJournalKey,
            scope: scope,
            persistence: originalPersistenceActor.makePersistence()
        )
        let envelope = try #require(
            await originalPersistenceActor.readPersistedEnvelope()
        )

        return (
            MosaicPrivateAlphaJournalPersistenceActor(
                persistedEnvelope: envelope
            ),
            fieldDerivedJournalKey,
            scope,
            envelope
        )
    }
}
#endif
