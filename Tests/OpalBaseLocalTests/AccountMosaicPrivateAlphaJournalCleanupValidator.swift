// AccountMosaicPrivateAlphaJournalCleanupValidator.swift

#if os(macOS)
import CryptoKit
import Foundation
import Testing
@_spi(MosaicPrivateAlpha) import OpalBase

@Suite(
    "OpalBase.Account private-alpha Mosaic journal cleanup",
    .tags(.unit, .wallet)
)
struct AccountMosaicPrivateAlphaJournalCleanupValidator {
    private typealias MosaicPrivateAlphaJournalFacade =
        OpalBase.Account.MosaicPrivateAlphaJournal

    @Test("Release journal persistence after authorization and retry outer cleanup")
    func releasePersistenceAfterAuthorizationAndRetryOuterCleanup() async throws {
        let persistenceActor = MosaicPrivateAlphaJournalPersistenceActor()
        let originalEnvelope: Data
        let disposition: MosaicPrivateAlphaJournalFacade.AttemptDisposition
        weak var lifetimeProbe:
            MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor?
        do {
            let strongLifetimeProbe =
                MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor()
            lifetimeProbe = strongLifetimeProbe
            let freshAttempt = try await MosaicPrivateAlphaJournalFacade
                .createFreshAttempt(
                    fieldDerivedJournalKey: makeFieldDerivedJournalKey(),
                    scope: makeScope(),
                    persistence: persistenceActor.makePersistence(
                        retaining: strongLifetimeProbe
                    )
                )
            originalEnvelope = try #require(
                await persistenceActor.readPersistedEnvelope()
            )
            disposition = try await MosaicPrivateAlphaJournalFacade
                .abandonFreshAttempt(freshAttempt)
            #expect(await strongLifetimeProbe.readAccessCount() == 1)
        }
        #expect(lifetimeProbe != nil)
        await persistenceActor.scheduleFailureForNextAuthorization()

        do {
            _ = try await MosaicPrivateAlphaJournalFacade
                .authorizeJournalErasure(
                    authorizedBy: disposition
                )
            Issue.record("Expected a mapped persistence failure")
        } catch let failure as MosaicPrivateAlphaJournalFacade.Failure {
            #expect(failure == .persistenceUnavailable)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }
        #expect(
            await persistenceActor.readPersistedEnvelope()
                == originalEnvelope
        )
        #expect(lifetimeProbe != nil)

        await persistenceActor.scheduleCancellationForNextAuthorization()
        do {
            _ = try await MosaicPrivateAlphaJournalFacade
                .authorizeJournalErasure(
                    authorizedBy: disposition
                )
            Issue.record("Expected authorization cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected CancellationError to remain unmapped")
        }
        #expect(
            await persistenceActor.readPersistedEnvelope()
                == originalEnvelope
        )
        #expect(lifetimeProbe != nil)

        let cleanupRequirement = try await MosaicPrivateAlphaJournalFacade
            .authorizeJournalErasure(
                authorizedBy: disposition
            )
        #expect(
            await persistenceActor.readPersistedEnvelope()
                == originalEnvelope
        )
        #expect(lifetimeProbe == nil)

        await persistenceActor.scheduleFailureForNextCleanup()
        do {
            try await MosaicPrivateAlphaJournalFacade.completeJournalErasure(
                requiredBy: cleanupRequirement,
                confirmOuterCleanup: { context in
                    try await persistenceActor
                        .removeOuterMaterialAndConfirmCleanup(matching: context)
                }
            )
            Issue.record("Expected outer cleanup failure")
        } catch let failure as MosaicPrivateAlphaJournalFacade.Failure {
            #expect(failure == .outerCleanupIncomplete)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }
        #expect(
            await persistenceActor.readPersistedEnvelope()
                == originalEnvelope
        )

        await persistenceActor.scheduleCancellationForNextCleanup()
        do {
            try await MosaicPrivateAlphaJournalFacade.completeJournalErasure(
                requiredBy: cleanupRequirement,
                confirmOuterCleanup: { context in
                    try await persistenceActor
                        .removeOuterMaterialAndConfirmCleanup(matching: context)
                }
            )
            Issue.record("Expected outer cleanup cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected CancellationError to remain unmapped")
        }
        #expect(
            await persistenceActor.readPersistedEnvelope()
                == originalEnvelope
        )

        try await MosaicPrivateAlphaJournalFacade.completeJournalErasure(
            requiredBy: cleanupRequirement,
            confirmOuterCleanup: { context in
                try await persistenceActor
                    .removeOuterMaterialAndConfirmCleanup(matching: context)
            }
        )
        #expect(await persistenceActor.readPersistedEnvelope() == nil)
    }

    private func makeFieldDerivedJournalKey() -> SymmetricKey {
        SymmetricKey(data: Data(repeating: 0x5c, count: 32))
    }

    private func makeScope() -> MosaicPrivateAlphaJournalFacade.Scope {
        .init(
            walletIdentifier: UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0x06, 0x01
                )
            ),
            journalIdentifier: UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0x06, 0x02
                )
            )
        )
    }
}
#endif
