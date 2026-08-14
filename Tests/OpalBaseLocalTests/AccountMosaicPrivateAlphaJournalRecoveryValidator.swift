// AccountMosaicPrivateAlphaJournalRecoveryValidator.swift

#if os(macOS)
import CryptoKit
import Foundation
import Testing
@_spi(MosaicPrivateAlpha) import OpalBase

@Suite("OpalBase.Account private-alpha Mosaic journal recovery", .tags(.unit, .wallet))
struct AccountMosaicPrivateAlphaJournalRecoveryValidator {
    private typealias Journal = OpalBase.Account.MosaicPrivateAlphaJournal

    @Test("Map persistence identity and authentication failures")
    func mapPrivateAlphaJournalFailures() async throws {
        let persistenceActor = MosaicPrivateAlphaJournalPersistenceActor()
        let key = makeFieldDerivedJournalKey()
        let scope = makeScope()
        let persistence = persistenceActor.makePersistence()

        do {
            _ = try await Journal.loadAuthenticatedRecovery(
                fieldDerivedJournalKey: key,
                scope: scope,
                persistence: MosaicPrivateAlphaJournalPersistenceActor()
                    .makePersistence()
            )
            Issue.record("Expected a missing journal")
        } catch let failure as Journal.Failure {
            #expect(failure == .notFound)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }

        let freshAttempt = try await Journal.createFreshAttempt(
            fieldDerivedJournalKey: key,
            scope: scope,
            persistence: persistence
        )

        do {
            _ = try await Journal.createFreshAttempt(
                fieldDerivedJournalKey: key,
                scope: scope,
                persistence: persistence
            )
            Issue.record("Expected exclusive creation to reject an existing journal")
        } catch let failure as Journal.Failure {
            #expect(failure == .attemptAlreadyExists)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }

        do {
            _ = try await Journal.loadAuthenticatedRecovery(
                fieldDerivedJournalKey: makeFieldDerivedJournalKey(byte: 0x6d),
                scope: scope,
                persistence: persistence
            )
            Issue.record("Expected the wrong field key to fail authentication")
        } catch let failure as Journal.Failure {
            #expect(failure == .journalIntegrityFailed)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }

        do {
            _ = try await Journal.loadAuthenticatedRecovery(
                fieldDerivedJournalKey: key,
                scope: makeScope(journalIdentifierLastByte: 0x02),
                persistence: persistence
            )
            Issue.record("Expected a substituted journal scope to fail authentication")
        } catch let failure as Journal.Failure {
            #expect(failure == .journalIntegrityFailed)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }

        do {
            _ = try await Journal.createFreshAttempt(
                fieldDerivedJournalKey: makeFieldDerivedJournalKey(byteCount: 16),
                scope: makeScope(journalIdentifierLastByte: 0x02),
                persistence: MosaicPrivateAlphaJournalPersistenceActor()
                    .makePersistence()
            )
            Issue.record("Expected a non-256-bit field key to be rejected")
        } catch let failure as Journal.Failure {
            #expect(failure == .invalidJournalKey)
        } catch {
            Issue.record("Expected a mapped journal failure")
        }

        let disposition = try await Journal.abandonFreshAttempt(freshAttempt)
        try await Journal.eraseJournal(authorizedBy: disposition)
    }

    @Test("Load authenticated recovery from fresh-process inputs")
    func loadAuthenticatedRecoveryFromFreshProcessInputs() async throws {
        let journalProbe = try await MosaicAttemptJournalProbeActor
            .makeAuthenticatedForPrivateAlphaTesting()
        let envelope = try #require(
            await journalProbe.readPersistedEnvelope()
        )
        let fieldDerivedJournalKey = await journalProbe
            .readFieldDerivedJournalKey()
        let identifiers = await journalProbe.readJournalScopeIdentifiers()
        let persistenceActor = MosaicPrivateAlphaJournalPersistenceActor(
            persistedEnvelope: envelope
        )

        let loadResult = try await Journal.loadAuthenticatedRecovery(
            fieldDerivedJournalKey: fieldDerivedJournalKey,
            scope: .init(
                walletIdentifier: identifiers.walletIdentifier,
                journalIdentifier: identifiers.journalIdentifier
            ),
            persistence: persistenceActor.makePersistence()
        )
        switch consume loadResult {
        case .abandonedFreshAttempt:
            Issue.record("Expected nonempty authenticated recovery")
        case .loadedRecovery:
            break
        }
        #expect(await persistenceActor.readPersistedEnvelope() == envelope)
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
