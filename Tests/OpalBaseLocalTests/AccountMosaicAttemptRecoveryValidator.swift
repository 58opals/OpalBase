// AccountMosaicAttemptRecoveryValidator.swift

#if os(macOS)
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

@Suite("OpalBase.Account Mosaic recovery and broadcast", .tags(.unit, .wallet))
struct AccountMosaicAttemptRecoveryValidator {
    typealias Planner = OpalBase.Account.MosaicAttemptRecoveryPlanner

    @Test("Derive conservative recovery at every write-ahead boundary")
    func deriveRecoveryAtEveryBoundary() async throws {
        let prepared = try await makeCommittedAttempt()
        let records = await prepared.fixture.journalProbe.readRecords()
        #expect(records.count == 6)

        #expect(
            try Planner.plan(for: Array(records.prefix(1)))
                == .releaseBeforeSigning(prepared.lease.reference)
        )
        #expect(
            try Planner.plan(for: Array(records.prefix(2)))
                == .releaseBeforeSigning(prepared.lease.reference)
        )
        #expect(
            try Planner.plan(for: Array(records.prefix(3)))
                == .reconcileSigningIntent(
                    reference: prepared.lease.reference,
                    request: prepared.request
                )
        )
        #expect(
            try Planner.plan(for: Array(records.prefix(4)))
                == .reconcileLocallySignedTransaction(
                    reference: prepared.lease.reference,
                    transaction: prepared.finalized
                )
        )
        #expect(
            try Planner.plan(for: Array(records.prefix(5)))
                == .finishCommit(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete
                )
        )
        #expect(
            try Planner.plan(for: records)
                == .broadcast(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete
                )
        )

        #expect(throws: Planner.Error.invalidTransition) {
            _ = try Planner.plan(for: [records[0], records[4]])
        }
        #expect(throws: Planner.Error.invalidFirstRecord) {
            _ = try Planner.plan(for: [records[1]])
        }
        let otherReference = OpalFusion.Host.MosaicReservationReference(
            identifier: UUID(),
            generation: prepared.lease.reference.generation
        )
        #expect(throws: Planner.Error.reservationReferenceMismatch) {
            _ = try Planner.plan(
                for: [records[0], .releaseIntent(otherReference)]
            )
        }

        var conflictingBytes = prepared.complete.transactionBytes
        conflictingBytes[conflictingBytes.index(before: conflictingBytes.endIndex)] ^= 0x01
        let conflictingTransaction = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: conflictingBytes
        )
        #expect(throws: Planner.Error.conflictingTransaction) {
            _ = try Planner.plan(
                for: Array(records.prefix(5)) + [
                    .committed(
                        reference: prepared.lease.reference,
                        transaction: conflictingTransaction
                    )
                ]
            )
        }
    }

    @Test("A pre-sign release is terminal and idempotently recoverable")
    func recoverReleasedAttempt() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(transactionPolicy: policy)
        let lease = try await fixture.reserve()
        try await fixture.host.releaseMosaicReservation(lease.reference)

        let records = await fixture.journalProbe.readRecords()
        #expect(records.count == 4)
        #expect(try Planner.plan(for: records) == .released)
    }

    @Test("Persist broadcast intent before I/O and retry only exact bytes")
    func persistBroadcastIntentBeforeIO() async throws {
        let prepared = try await makeCommittedAttempt()
        let broadcastProbe = MosaicBroadcastProbeActor(
            journalProbe: prepared.fixture.journalProbe,
            failuresRemaining: 1
        )
        let coordinator = OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            reservationReference: prepared.lease.reference,
            journal: prepared.fixture.journalProbe.makeJournal(),
            transactionClient: broadcastProbe.makeClient()
        )

        await #expect(throws: MosaicBroadcastProbeFailure.scripted) {
            _ = try await coordinator.broadcast(prepared.complete)
        }
        #expect(await broadcastProbe.readObservedPersistedIntent())
        #expect(
            try Planner.plan(
                for: await prepared.fixture.journalProbe.readRecords()
            ) == .broadcast(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        )

        let hash = try await coordinator.broadcast(prepared.complete)
        let duplicateHash = try await coordinator.broadcast(prepared.complete)
        #expect(hash == duplicateHash)
        #expect(await broadcastProbe.readBroadcasts().count == 2)
        #expect(
            try Planner.plan(
                for: await prepared.fixture.journalProbe.readRecords()
            ) == .complete(hash)
        )

        var conflictingBytes = prepared.complete.transactionBytes
        conflictingBytes[conflictingBytes.index(before: conflictingBytes.endIndex)] ^= 0x01
        let conflicting = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: conflictingBytes
        )
        await #expect(throws: OpalBase.Account.MosaicHostFailure.conflictingBroadcast) {
            _ = try await coordinator.broadcast(conflicting)
        }
    }

    @Test("A failed locally-signed journal write quarantines inputs without resigning")
    func quarantineAfterLocallySignedPersistenceFailure() async throws {
        let journalProbe = MosaicAttemptJournalProbeActor(
            failingAppendIndices: [3]
        )
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)

        await #expect(throws: OpalBase.Account.MosaicHostFailure.journalPersistenceFailed) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        #expect(await fixture.host.readSigningInvocationCount() == 1)
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            try await fixture.host.releaseMosaicReservation(lease.reference)
        }
        #expect(
            try Planner.plan(for: await journalProbe.readRecords())
                == .reconcileSigningIntent(
                    reference: lease.reference,
                    request: request
                )
        )

        let finalized = try await fixture.host.finalizeMosaicTransaction(for: request)
        #expect(await fixture.host.readSigningInvocationCount() == 1)
        #expect(
            try Planner.plan(for: await journalProbe.readRecords())
                == .reconcileLocallySignedTransaction(
                    reference: lease.reference,
                    transaction: finalized
                )
        )
    }

    @Test("Retry exact broadcast after accepted-result persistence fails")
    func retryBroadcastAfterAcceptedPersistenceFailure() async throws {
        let journalProbe = MosaicAttemptJournalProbeActor(
            failingAppendIndices: [7]
        )
        let prepared = try await makeCommittedAttempt(journalProbe: journalProbe)
        let broadcastProbe = MosaicBroadcastProbeActor(journalProbe: journalProbe)
        let coordinator = OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            reservationReference: prepared.lease.reference,
            journal: journalProbe.makeJournal(),
            transactionClient: broadcastProbe.makeClient()
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.journalPersistenceFailed) {
            _ = try await coordinator.broadcast(prepared.complete)
        }
        #expect(await broadcastProbe.readBroadcasts().count == 1)
        #expect(
            try Planner.plan(for: await journalProbe.readRecords())
                == .broadcast(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete
                )
        )

        let hash = try await coordinator.broadcast(prepared.complete)
        #expect(await broadcastProbe.readBroadcasts().count == 2)
        #expect(
            try Planner.plan(for: await journalProbe.readRecords())
                == .complete(hash)
        )
    }

    @Test("Retry an exact commit after its terminal journal write fails")
    func retryCommitPersistenceExactly() async throws {
        let journalProbe = MosaicAttemptJournalProbeActor(
            failingAppendIndices: [5]
        )
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let finalized = try await fixture.host.finalizeMosaicTransaction(for: request)
        let complete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: finalized.signedFusionTransactionBytes
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.journalPersistenceFailed) {
            try await fixture.host.commitMosaicReservation(
                lease.reference,
                completeTransaction: complete
            )
        }
        #expect(
            try Planner.plan(for: await journalProbe.readRecords())
                == .finishCommit(reference: lease.reference, transaction: complete)
        )

        try await fixture.host.commitMosaicReservation(
            lease.reference,
            completeTransaction: complete
        )
        #expect(
            try Planner.plan(for: await journalProbe.readRecords())
                == .broadcast(reference: lease.reference, transaction: complete)
        )
    }

    private func makeCommittedAttempt(
        journalProbe: MosaicAttemptJournalProbeActor = .init()
    ) async throws -> (
        fixture: MosaicHostFixture,
        lease: OpalFusion.Host.MosaicReservationLease,
        request: OpalFusion.Host.MosaicTransactionSigningRequest,
        finalized: OpalFusion.Host.FinalizedTransaction,
        complete: OpalFusion.Host.MosaicCompleteTransaction
    ) {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let finalized = try await fixture.host.finalizeMosaicTransaction(for: request)
        let complete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: finalized.signedFusionTransactionBytes
        )
        try await fixture.host.commitMosaicReservation(
            lease.reference,
            completeTransaction: complete
        )
        return (fixture, lease, request, finalized, complete)
    }
}
#endif
