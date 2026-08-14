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
                .scheduleCancellationForNextDeletion()
            do {
                try await Journal.eraseJournal(authorizedBy: disposition)
                Issue.record("Expected recovered erasure cancellation")
            } catch is CancellationError {
            } catch {
                Issue.record("Expected CancellationError to remain unmapped")
            }
            #expect(
                await fixture.persistenceActor.readPersistedEnvelope()
                    == fixture.envelope
            )

            try await Journal.eraseJournal(authorizedBy: disposition)
            #expect(
                await fixture.persistenceActor.readPersistedEnvelope() == nil
            )
        case .loadedRecovery:
            Issue.record("Expected authenticated empty-journal erasure authority")
        }
    }

    @Test("Preserve replacement bytes from recovered empty-journal erasure")
    func preserveReplacementWhenRecoveredErasureIsStale() async throws {
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
                try await Journal.eraseJournal(authorizedBy: disposition)
                Issue.record("Expected recovered erasure to reject replacement bytes")
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
