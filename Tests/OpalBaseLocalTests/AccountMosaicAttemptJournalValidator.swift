// AccountMosaicAttemptJournalValidator.swift

#if os(macOS)
import CryptoKit
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

@Suite("OpalBase.Account Mosaic attempt journal", .tags(.unit, .wallet))
struct AccountMosaicAttemptJournalValidator {
    @Test(
        "Reentrant journal writers cannot overwrite a newer snapshot",
        .timeLimit(.minutes(1))
    )
    func rejectReentrantStaleJournalWrite() async throws {
        let template = try await makeCommittedAttempt()
        let firstRecord = try #require(
            await template.fixture.journalProbe.readRecords().first
        )
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 0,
            suspensionProbe: suspension
        )
        let journal = try await journalProbe.makeFreshJournalForTesting()

        let firstAppend = Task {
            try await journal.append(firstRecord)
        }
        await suspension.waitUntilSuspended()
        let secondAppend = Task {
            try await journal.append(firstRecord)
        }
        try await secondAppend.value
        await suspension.resume()
        await #expect(
            throws: OpalBase.Account.MosaicAttemptJournalStore.Failure
                .staleSnapshot
        ) {
            try await firstAppend.value
        }
        #expect(await journalProbe.readRecords() == [firstRecord])
    }

    @Test("Journal snapshots authenticate every record and wallet scope")
    func authenticateDurableJournalSnapshot() async throws {
        let prepared = try await makeCommittedAttempt()
        let committedRecords = await prepared.fixture.journalProbe.readRecords()
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x5a, count: 32)
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
            .releaseIntent(prepared.lease.reference),
            .released(prepared.lease.reference)
        ]
        let key = SymmetricKey(data: Data(repeating: 0x41, count: 32))
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
            authenticationKey: SymmetricKey(
                data: Data(repeating: 0x42, count: 32)
            ),
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
        futureVersion[8] = 2
        #expect(
            throws: OpalBase.Account.MosaicAttemptJournalCodec.Failure
                .unsupportedVersion(2)
        ) {
            _ = try codec.open(futureVersion)
        }
    }
}
#endif
