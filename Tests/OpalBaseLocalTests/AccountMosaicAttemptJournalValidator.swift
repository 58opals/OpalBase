// AccountMosaicAttemptJournalValidator.swift

#if os(macOS)
import Foundation
import OpalFusion
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase

@Suite("OpalBase.Account Mosaic attempt journal", .tags(.unit, .wallet))
struct AccountMosaicAttemptJournalValidator {
    @Test(
        "Reentrant journal writers cannot overwrite a newer snapshot",
        .timeLimit(.minutes(1))
    )
    func rejectReentrantStaleJournalWrite() async throws {
        let template = try await makeCommittedAttempt()
        let templateRecords = await template.fixture.journalProbe.readRecords()
        let bindingRecord = templateRecords[0]
        let concurrentRecord = templateRecords[1]
        guard case let .attemptBinding(binding) = bindingRecord else {
            Issue.record("Expected attempt binding")
            return
        }
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 0,
            suspensionProbe: suspension
        )
        let journal = try await journalProbe.makeBoundJournalForTesting(binding)

        let firstAppend = Task {
            try await journal.append(concurrentRecord)
        }
        await suspension.waitUntilSuspended()
        let secondAppend = Task {
            try await journal.append(concurrentRecord)
        }
        try await secondAppend.value
        await suspension.resume()
        await #expect(
            throws: OpalBase.Account.MosaicAttemptJournalStore.Failure
                .staleSnapshot
        ) {
            try await firstAppend.value
        }
        #expect(
            await journalProbe.readRecords()
                == [bindingRecord, concurrentRecord]
        )
    }

    @Test("Journal snapshots authenticate every record and wallet scope")
    func authenticateDurableJournalSnapshot() async throws {
        let prepared = try await makeCommittedAttempt()
        let committedRecords = await prepared.fixture.journalProbe.readRecords()
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(
                Data(prepared.complete.transactionBytes)
            )
        )
        let blockHash = Data(repeating: 0x5a, count: 32)
        let chainObservation = try #require(
            OpalBase.Account.MosaicAttemptChainObservation(
                transactionHash: transactionHash,
                presence: .present(blockHash: blockHash, confirmations: 2)
            )
        )
        let records = committedRecords + [
            .broadcastApproved(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            ),
            .broadcastIntent(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            ),
            .broadcastAccepted(
                reference: prepared.lease.reference,
                transaction: prepared.complete,
                transactionHash: transactionHash
            ),
            .chainObservation(
                reference: prepared.lease.reference,
                transaction: prepared.complete,
                observation: chainObservation
            ),
            .terminalDisposition(
                reference: prepared.lease.reference,
                transaction: prepared.complete,
                disposition: .chainFinalized(
                    transactionHash: transactionHash,
                    blockHash: blockHash,
                    confirmations: 2
                )
            )
        ]
        let key = makeJournalKey(byte: 0x41)
        let scope = OpalBase.Account.MosaicAttemptJournalCodec.Scope(
            walletIdentifier: try #require(
                UUID(uuidString: "00000000-0000-0000-0000-000000000041")
            ),
            journalIdentifier: try #require(
                UUID(uuidString: "00000000-0000-0000-0000-000000000042")
            )
        )
        let codec = try OpalBase.Account.MosaicAttemptJournalCodec(
            authenticationKey: key,
            scope: scope
        )
        let envelope = try codec.seal(records: records)
        #expect(try codec.open(envelope) == records)

        let wrongKeyCodec = try OpalBase.Account.MosaicAttemptJournalCodec(
            authenticationKey: makeJournalKey(byte: 0x42),
            scope: scope
        )
        #expect(
            throws: OpalBase.Account.MosaicAttemptJournalCodec.Failure
                .authenticationFailed
        ) {
            _ = try wrongKeyCodec.open(envelope)
        }

        let wrongScopeCodec = try OpalBase.Account.MosaicAttemptJournalCodec(
            authenticationKey: key,
            scope: .init(
                walletIdentifier: scope.walletIdentifier,
                journalIdentifier: UUID()
            )
        )
        #expect(
            throws: OpalBase.Account.MosaicAttemptJournalCodec.Failure
                .authenticationFailed
        ) {
            _ = try wrongScopeCodec.open(envelope)
        }

        var modified = envelope
        modified[modified.index(before: modified.endIndex)] ^= 0x01
        #expect(
            throws: OpalBase.Account.MosaicAttemptJournalCodec.Failure
                .authenticationFailed
        ) {
            _ = try codec.open(modified)
        }
        #expect(
            throws: OpalBase.Account.MosaicAttemptJournalCodec.Failure
                .authenticationFailed
        ) {
            _ = try codec.open(Data(envelope.dropLast()))
        }

        var futureVersion = envelope
        futureVersion[8] = 3
        #expect(
            throws: OpalBase.Account.MosaicAttemptJournalCodec.Failure
                .unsupportedVersion(3)
        ) {
            _ = try codec.open(futureVersion)
        }
    }

    @Test("Pre-binding version-one snapshots are explicitly unsupported")
    func rejectPreBindingVersionOneSnapshot() throws {
        let key = makeJournalKey(byte: 0x41)
        let scope = OpalBase.Account.MosaicAttemptJournalCodec.Scope(
            walletIdentifier: try #require(
                UUID(uuidString: "00000000-0000-0000-0000-000000000041")
            ),
            journalIdentifier: try #require(
                UUID(uuidString: "00000000-0000-0000-0000-000000000042")
            )
        )
        let codec = try OpalBase.Account.MosaicAttemptJournalCodec(
            authenticationKey: key,
            scope: scope
        )
        let exactVersionOneEmptyEnvelope = try #require(
            Data(
                base64Encoded:
                    "T1BNSlJOMDEBAAECAwQFBgcICQoLNbE6STV8MI0+GZUdnPAWv91PdvY0Cux1ZTTR/y4R+Gtf15pMoX9LDM6lOg=="
            )
        )

        #expect(exactVersionOneEmptyEnvelope[8] == 1)
        #expect(
            throws: OpalBase.Account.MosaicAttemptJournalCodec.Failure
                .unsupportedVersion(1)
        ) {
            _ = try codec.open(exactVersionOneEmptyEnvelope)
        }

        let versionTwoEnvelope = try codec.seal(records: [])
        #expect(versionTwoEnvelope[8] == 2)
        #expect(try codec.open(versionTwoEnvelope).isEmpty)
    }

    @Test("Open a frozen pre-OpalCrypto version-two snapshot")
    func openFrozenVersionTwoSnapshot() throws {
        let scope = OpalBase.Account.MosaicAttemptJournalCodec.Scope(
            walletIdentifier: try #require(
                UUID(uuidString: "00000000-0000-0000-0000-000000000041")
            ),
            journalIdentifier: try #require(
                UUID(uuidString: "00000000-0000-0000-0000-000000000042")
            )
        )
        let codec = try OpalBase.Account.MosaicAttemptJournalCodec(
            authenticationKey: makeJournalKey(byte: 0x41),
            scope: scope
        )
        // Sealed by the former CryptoKit implementation with nonce bytes 0x00...0x0b.
        let frozenVersionTwoEnvelope = try #require(
            Data(
                base64Encoded:
                    "T1BNSlJOMDECAAECAwQFBgcICQoLVzTRDoA53DvzSYOQLqygydlNrI3Fh/Hld6j4LhcjGG8KUrvMuF7A8jQPxw=="
            )
        )

        #expect(frozenVersionTwoEnvelope[8] == 2)
        #expect(try codec.open(frozenVersionTwoEnvelope).isEmpty)
    }

    @Test(
        "Deterministic mutations cover the authenticated journal root",
        .timeLimit(.minutes(1))
    )
    func mutateAuthenticatedJournalRoot() throws {
        let codec = try OpalBase.Account.MosaicAttemptJournalCodec(
            authenticationKey: makeJournalKey(byte: 0x43),
            scope: .init(
                walletIdentifier: try #require(
                    UUID(uuidString: "00000000-0000-0000-0000-000000000043")
                ),
                journalIdentifier: try #require(
                    UUID(uuidString: "00000000-0000-0000-0000-000000000044")
                )
            )
        )
        let envelope = try codec.seal(records: [])
        let vector = MosaicDeterministicParserMutationVector(
            name: "OpalBase authenticated Mosaic journal",
            seedBytes: envelope
        ) { bytes in
            let records = try codec.open(bytes)
            return records.isEmpty
        }

        try MosaicDeterministicParserMutationCampaign.validate(
            [vector],
            seed: 0x3C6E_F372_FE94_F82B,
            seededMutationCount: 32
        )
    }

    private func makeJournalKey(
        byte: UInt8
    ) -> OpalBase.Account.MosaicPrivateAlphaJournal.JournalKey {
        try! .init(
            fieldDerivedKeyMaterial: Data(repeating: byte, count: 32)
        )
    }
}
#endif
