// AccountMosaicAttemptRecoveryPlannerValidator.swift

#if os(macOS)
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

@Suite("OpalBase.Account Mosaic attempt recovery planner", .tags(.unit, .wallet))
struct AccountMosaicAttemptRecoveryPlannerValidator {
    typealias Planner = OpalBase.Account.MosaicAttemptRecoveryPlanner

    @Test("Derive conservative recovery at every write-ahead boundary")
    func deriveRecoveryAtEveryBoundary() async throws {
        #expect(try Planner.plan(for: []) == .noAction)
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
                == .broadcastApprovalRequired(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete,
                    broadcastIntentPersisted: false
                )
        )
        let approvedRecords = records + [
            .broadcastApproved(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        ]
        #expect(
            try Planner.plan(for: approvedRecords)
                == .resumeApprovedBroadcast(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete,
                    broadcastIntentPersisted: false
                )
        )
        let approvedIntentRecords = approvedRecords + [
            .broadcastIntent(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        ]
        #expect(
            try Planner.plan(for: approvedIntentRecords)
                == .resumeApprovedBroadcast(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete,
                    broadcastIntentPersisted: true
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
        #expect(throws: Planner.Error.conflictingTransaction) {
            _ = try Planner.plan(
                for: records + [
                    .broadcastApproved(
                        reference: prepared.lease.reference,
                        transaction: conflictingTransaction
                    )
                ]
            )
        }
        #expect(throws: Planner.Error.conflictingTransaction) {
            _ = try Planner.plan(
                for: approvedRecords + [
                    .broadcastIntent(
                        reference: prepared.lease.reference,
                        transaction: conflictingTransaction
                    )
                ]
            )
        }
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x55, count: 32)
        )
        #expect(throws: Planner.Error.conflictingTransaction) {
            _ = try Planner.plan(
                for: approvedIntentRecords + [
                    .broadcastAccepted(
                        reference: prepared.lease.reference,
                        transaction: conflictingTransaction,
                        transactionHash: transactionHash
                    )
                ]
            )
        }
    }

    @Test("A failed terminal release write yields an exact recovery plan")
    func recoverReleaseAfterTerminalPersistenceFailure() async throws {
        let journalProbe = MosaicAttemptJournalProbeActor(failingAppendIndices: [3])
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let lease = try await fixture.reserve()

        await #expect(throws: OpalBase.Account.MosaicHostFailure.journalPersistenceFailed) {
            try await fixture.host.releaseMosaicReservation(lease.reference)
        }
        let records = await journalProbe.readRecords()
        #expect(records.count == 3)
        #expect(try Planner.plan(for: records) == .finishRelease(lease.reference))
        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
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
                == .broadcastApprovalRequired(
                    reference: lease.reference,
                    transaction: complete,
                    broadcastIntentPersisted: false
                )
        )
    }
}
#endif
