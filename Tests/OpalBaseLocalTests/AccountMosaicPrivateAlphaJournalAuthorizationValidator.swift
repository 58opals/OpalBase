// AccountMosaicPrivateAlphaJournalAuthorizationValidator.swift

#if os(macOS)
import CryptoKit
import Foundation
import Testing
@_spi(MosaicPrivateAlpha) import OpalBase

@Suite(
    "OpalBase.Account private-alpha Mosaic journal authorization",
    .tags(.unit, .wallet)
)
struct AccountMosaicPrivateAlphaJournalAuthorizationValidator {
    private typealias MosaicPrivateAlphaJournalFacade =
        OpalBase.Account.MosaicPrivateAlphaJournal

    @Test("Retry exact authorization after a durable commit reports failure")
    func retryExactAuthorizationAfterCommitThenFailure() async throws {
        let persistenceActor = MosaicPrivateAlphaJournalPersistenceActor()
        let scope = makeScope()
        let disposition: MosaicPrivateAlphaJournalFacade.AttemptDisposition
        let expectedContext: MosaicPrivateAlphaJournalFacade.CleanupContext
        weak var lifetimeProbe:
            MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor?
        do {
            let strongLifetimeProbe =
                MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor()
            lifetimeProbe = strongLifetimeProbe
            let freshAttempt = try await MosaicPrivateAlphaJournalFacade
                .createFreshAttempt(
                    fieldDerivedJournalKey: makeFieldDerivedJournalKey(),
                    scope: scope,
                    persistence: persistenceActor.makePersistence(
                        retaining: strongLifetimeProbe
                    )
                )
            let envelope = try #require(
                await persistenceActor.readPersistedEnvelope()
            )
            expectedContext = try #require(
                MosaicPrivateAlphaJournalFacade.CleanupContext(
                    scope: scope,
                    expectedEnvelopeSHA256: Data(
                        SHA256.hash(data: envelope)
                    )
                )
            )
            disposition = try await MosaicPrivateAlphaJournalFacade
                .abandonFreshAttempt(freshAttempt)
        }

        await persistenceActor
            .scheduleCommitThenFailureForNextAuthorization()
        do {
            _ = try await MosaicPrivateAlphaJournalFacade
                .authorizeJournalErasure(
                    authorizedBy: disposition
                )
            Issue.record("Expected outcome-uncertain authorization failure")
        } catch let failure as MosaicPrivateAlphaJournalFacade.Failure {
            #expect(failure == .persistenceUnavailable)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }
        #expect(lifetimeProbe != nil)
        #expect(
            await persistenceActor.readJournalState()
                == .journalErasureAuthorized(expectedContext)
        )

        let cleanupRequirement = try await MosaicPrivateAlphaJournalFacade
            .authorizeJournalErasure(
                authorizedBy: disposition
            )
        #expect(cleanupRequirement.context == expectedContext)
        #expect(lifetimeProbe == nil)
        try await MosaicPrivateAlphaJournalFacade.completeJournalErasure(
            requiredBy: cleanupRequirement,
            confirmOuterCleanup: { context in
                try await persistenceActor
                    .removeOuterMaterialAndConfirmCleanup(matching: context)
            }
        )
    }

    @Test("Read back exact authorization after a durable commit reports cancellation")
    func readBackExactAuthorizationAfterCommitThenCancellation() async throws {
        let persistenceActor = MosaicPrivateAlphaJournalPersistenceActor()
        let scope = makeScope(journalIdentifierLastByte: 0x02)
        let expectedContext: MosaicPrivateAlphaJournalFacade.CleanupContext
        weak var authorizationLifetimeProbe:
            MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor?
        do {
            let strongLifetimeProbe =
                MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor()
            authorizationLifetimeProbe = strongLifetimeProbe
            let freshAttempt = try await MosaicPrivateAlphaJournalFacade
                .createFreshAttempt(
                    fieldDerivedJournalKey: makeFieldDerivedJournalKey(byte: 0x6d),
                    scope: scope,
                    persistence: persistenceActor.makePersistence(
                        retaining: strongLifetimeProbe
                    )
                )
            let envelope = try #require(
                await persistenceActor.readPersistedEnvelope()
            )
            expectedContext = try #require(
                MosaicPrivateAlphaJournalFacade.CleanupContext(
                    scope: scope,
                    expectedEnvelopeSHA256: Data(
                        SHA256.hash(data: envelope)
                    )
                )
            )
            let disposition = try await MosaicPrivateAlphaJournalFacade
                .abandonFreshAttempt(freshAttempt)
            await persistenceActor
                .scheduleCommitThenCancellationForNextAuthorization()
            do {
                _ = try await MosaicPrivateAlphaJournalFacade
                    .authorizeJournalErasure(
                        authorizedBy: disposition
                    )
                Issue.record("Expected outcome-uncertain cancellation")
            } catch is CancellationError {
            } catch {
                Issue.record("Expected CancellationError to remain unmapped")
            }
            #expect(authorizationLifetimeProbe != nil)
            let retriedRequirement = try await MosaicPrivateAlphaJournalFacade
                .authorizeJournalErasure(authorizedBy: disposition)
            #expect(retriedRequirement.context == expectedContext)
        }
        #expect(authorizationLifetimeProbe == nil)
        #expect(
            await persistenceActor.readJournalState()
                == .journalErasureAuthorized(expectedContext)
        )

        let cleanupRequirement:
            MosaicPrivateAlphaJournalFacade.CleanupRequirement
        weak var readBackLifetimeProbe:
            MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor?
        do {
            let strongLifetimeProbe =
                MosaicPrivateAlphaJournalPersistenceLifetimeProbeActor()
            readBackLifetimeProbe = strongLifetimeProbe
            guard let loadedRequirement = try await MosaicPrivateAlphaJournalFacade
                .loadAuthorizedJournalCleanup(
                    scope: scope,
                    persistence: persistenceActor.makePersistence(
                        retaining: strongLifetimeProbe
                    )
                ) else {
                Issue.record("Expected durable authorization read-back")
                return
            }
            cleanupRequirement = loadedRequirement
        }
        #expect(readBackLifetimeProbe == nil)
        #expect(cleanupRequirement.context == expectedContext)
        try await MosaicPrivateAlphaJournalFacade.completeJournalErasure(
            requiredBy: cleanupRequirement,
            confirmOuterCleanup: { context in
                try await persistenceActor
                    .removeOuterMaterialAndConfirmCleanup(matching: context)
            }
        )
    }

    private func makeFieldDerivedJournalKey(
        byte: UInt8 = 0x5c
    ) -> SymmetricKey {
        SymmetricKey(data: Data(repeating: byte, count: 32))
    }

    private func makeScope(
        journalIdentifierLastByte: UInt8 = 0x01
    ) -> MosaicPrivateAlphaJournalFacade.Scope {
        .init(
            walletIdentifier: UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0x04, 0x01
                )
            ),
            journalIdentifier: UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, journalIdentifierLastByte
                )
            )
        )
    }
}
#endif
