// AccountMosaicPrivateAlphaJournalCorrelationValidator.swift

#if os(macOS)
import CryptoKit
import Foundation
import Testing
@_spi(MosaicPrivateAlpha) import OpalBase

@Suite(
    "OpalBase.Account private-alpha Mosaic journal cleanup correlation",
    .tags(.unit, .wallet)
)
struct AccountMosaicPrivateAlphaJournalCorrelationValidator {
    private typealias MosaicPrivateAlphaJournalFacade =
        OpalBase.Account.MosaicPrivateAlphaJournal

    @Test("Reject cleanup context from another encrypted attempt")
    func rejectCleanupContextFromAnotherEncryptedAttempt() async throws {
        let scope = makeScope()
        let firstPersistenceActor =
            MosaicPrivateAlphaJournalPersistenceActor()
        let secondPersistenceActor =
            MosaicPrivateAlphaJournalPersistenceActor()
        let firstFreshAttempt = try await MosaicPrivateAlphaJournalFacade
            .createFreshAttempt(
                fieldDerivedJournalKey: makeFieldDerivedJournalKey(byte: 0x71),
                scope: scope,
                persistence: firstPersistenceActor.makePersistence()
            )
        let secondFreshAttempt = try await MosaicPrivateAlphaJournalFacade
            .createFreshAttempt(
                fieldDerivedJournalKey: makeFieldDerivedJournalKey(byte: 0x72),
                scope: scope,
                persistence: secondPersistenceActor.makePersistence()
            )
        let firstDisposition = try await MosaicPrivateAlphaJournalFacade
            .abandonFreshAttempt(firstFreshAttempt)
        let secondDisposition = try await MosaicPrivateAlphaJournalFacade
            .abandonFreshAttempt(secondFreshAttempt)
        let firstCleanupRequirement = try await MosaicPrivateAlphaJournalFacade
            .authorizeJournalErasure(authorizedBy: firstDisposition)
        let secondCleanupRequirement = try await MosaicPrivateAlphaJournalFacade
            .authorizeJournalErasure(authorizedBy: secondDisposition)
        #expect(
            firstCleanupRequirement.context.expectedEnvelopeSHA256
                != secondCleanupRequirement.context.expectedEnvelopeSHA256
        )

        do {
            try await MosaicPrivateAlphaJournalFacade
                .completeJournalErasure(
                    requiredBy: firstCleanupRequirement,
                    confirmOuterCleanup: { context in
                        try await secondPersistenceActor
                            .removeOuterMaterialAndConfirmCleanup(
                                matching: context
                            )
                    }
                )
            Issue.record("Expected cross-attempt cleanup rejection")
        } catch let failure as MosaicPrivateAlphaJournalFacade.Failure {
            #expect(failure == .outerCleanupIncomplete)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }
        #expect(
            await secondPersistenceActor.readPersistedEnvelope() != nil
        )

        try await MosaicPrivateAlphaJournalFacade.completeJournalErasure(
            requiredBy: firstCleanupRequirement,
            confirmOuterCleanup: { context in
                try await firstPersistenceActor
                    .removeOuterMaterialAndConfirmCleanup(matching: context)
            }
        )
        try await MosaicPrivateAlphaJournalFacade.completeJournalErasure(
            requiredBy: secondCleanupRequirement,
            confirmOuterCleanup: { context in
                try await secondPersistenceActor
                    .removeOuterMaterialAndConfirmCleanup(matching: context)
            }
        )
    }

    private func makeFieldDerivedJournalKey(byte: UInt8) -> SymmetricKey {
        SymmetricKey(data: Data(repeating: byte, count: 32))
    }

    private func makeScope() -> MosaicPrivateAlphaJournalFacade.Scope {
        .init(
            walletIdentifier: UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0x05, 0x01
                )
            ),
            journalIdentifier: UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0x05, 0x02
                )
            )
        )
    }
}
#endif
