// AccountMosaicTransactionHostValidator+Concurrency.swift

#if os(macOS)
import OpalFusion
import Foundation
import Synchronization
import Testing
@testable import OpalBase

extension AccountMosaicTransactionHostValidator {
    @Test(
        "Reservation intent pins one exact request before suspension",
        .timeLimit(.minutes(1))
    )
    func pinReservationBeforeJournalSuspension() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 0,
            suspensionProbe: suspension
        )
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let firstReservation = Task {
            try await fixture.reserve()
        }
        await suspension.waitUntilSuspended()

        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            _ = try await fixture.reserve()
        }
        let replacement = try makeReplacementReservationRequest(for: fixture)
        await #expect(throws: OpalBase.Account.MosaicHostFailure.inPlaceRetryNotPermitted) {
            _ = try await fixture.host.reserveMosaicContribution(for: replacement)
        }

        await suspension.resume()
        let lease = try await firstReservation.value
        let records = await journalProbe.readRecords()
        #expect(records.count == 2)
        if case .reservationIntent(let reference, let request, _, _)? = records.first {
            #expect(reference == lease.reference)
            #expect(request == fixture.reservationRequest)
        } else {
            Issue.record("Expected one pinned reservation intent")
        }
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test(
        "Reservation persistence cannot return an expired lease",
        .timeLimit(.minutes(1))
    )
    func expireDuringReservedPersistence() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 1,
            suspensionProbe: suspension
        )
        let clock = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe,
            currentDate: { clock.withLock { $0 } }
        )
        let reservation = Task {
            try await fixture.reserve()
        }
        await suspension.waitUntilSuspended()
        clock.withLock {
            $0 = fixture.reservationRequest.expiresAt
        }
        await suspension.resume()

        await #expect(throws: OpalBase.Account.MosaicHostFailure.reservationExpired) {
            _ = try await reservation.value
        }
        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
        let records = await journalProbe.readRecords()
        #expect(records.count == 4)
        if case .released = records[3] {
            // The expired lease was cleaned up before it could be returned.
        } else {
            Issue.record("Expected expired reservation cleanup to reach released state")
        }
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            _ = try await fixture.reserve()
        }
    }

    @Test(
        "Cancellation cannot cross reservation persistence into a lease",
        .timeLimit(.minutes(1))
    )
    func cancelDuringReservationPersistence() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 1,
            suspensionProbe: suspension
        )
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let reservation = Task {
            try await fixture.reserve()
        }
        await suspension.waitUntilSuspended()
        reservation.cancel()
        await suspension.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await reservation.value
        }
        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
        let records = await journalProbe.readRecords()
        #expect(records.count == 4)
        if case .released = records[3] {
            // Cancellation reached conservative cleanup before any lease escaped.
        } else {
            Issue.record("Expected canceled reservation to finish release cleanup")
        }
    }

    @Test(
        "Cancellation after reservation intent cannot mutate the wallet",
        .timeLimit(.minutes(1))
    )
    func cancelAfterReservationIntentPersistence() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 0,
            suspensionProbe: suspension
        )
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let reservation = Task {
            try await fixture.reserve()
        }
        await suspension.waitUntilSuspended()
        reservation.cancel()
        await suspension.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await reservation.value
        }
        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
        #expect(await journalProbe.readRecords().count == 1)
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            _ = try await fixture.reserve()
        }
    }

    @Test(
        "Finalization pins one request while transaction policy suspends",
        .timeLimit(.minutes(1))
    )
    func quarantineReleaseDuringPolicyValidation() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let policyProbe = MosaicPolicyProbeActor(suspensionProbe: suspension)
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: await policyProbe.transactionPolicy
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let firstFinalization = Task {
            try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        await suspension.waitUntilSuspended()

        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        let conflicting = try fixture.makeSigningRequest(
            lease: lease,
            transcriptByte: 0x45
        )
        await #expect(throws: OpalBase.Account.MosaicHostFailure.conflictingFinalization) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: conflicting)
        }
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            try await fixture.host.releaseMosaicReservation(lease.reference)
        }

        await suspension.resume()
        _ = try await firstFinalization.value
        #expect(await policyProbe.readInvocationCount() == 1)
        #expect(await fixture.host.readSigningInvocationCount() == 1)
    }

    @Test(
        "Policy validation cannot cross the reservation deadline into signing",
        .timeLimit(.minutes(1))
    )
    func expireAfterPolicyValidationBeforeSigning() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let policyProbe = MosaicPolicyProbeActor(suspensionProbe: suspension)
        let clock = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: await policyProbe.transactionPolicy,
            currentDate: { clock.withLock { $0 } }
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let finalization = Task {
            try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        await suspension.waitUntilSuspended()
        clock.withLock { $0 = lease.expiresAt }
        await suspension.resume()

        await #expect(throws: OpalBase.Account.MosaicHostFailure.reservationExpired) {
            _ = try await finalization.value
        }
        #expect(await policyProbe.readInvocationCount() == 1)
        #expect(await fixture.host.readSigningInvocationCount() == 0)
        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
        let records = await fixture.journalProbe.readRecords()
        #expect(records.count == 4)
        if case .releaseIntent(let reference) = records[2] {
            #expect(reference == lease.reference)
        } else {
            Issue.record("Expected expiry to persist release intent before cleanup")
        }
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test(
        "Cancellation after policy validation cannot enter signing",
        .timeLimit(.minutes(1))
    )
    func cancelDuringPolicyValidation() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let policyProbe = MosaicPolicyProbeActor(suspensionProbe: suspension)
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: await policyProbe.transactionPolicy
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let finalization = Task {
            try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        await suspension.waitUntilSuspended()
        finalization.cancel()
        await suspension.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await finalization.value
        }
        #expect(await fixture.host.readSigningInvocationCount() == 0)
        #expect(await fixture.journalProbe.readRecords().count == 2)
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test(
        "Signing intent quarantines release before journal suspension",
        .timeLimit(.minutes(1))
    )
    func quarantineReleaseDuringSigningIntentPersistence() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 2,
            suspensionProbe: suspension
        )
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let firstFinalization = Task {
            try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        await suspension.waitUntilSuspended()

        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            try await fixture.host.releaseMosaicReservation(lease.reference)
        }
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        #expect(await fixture.host.readSigningInvocationCount() == 0)
        #expect(await journalProbe.readRecords().count == 2)

        await suspension.resume()
        _ = try await firstFinalization.value
        #expect(await fixture.host.readSigningInvocationCount() == 1)
        #expect(await journalProbe.readRecords().count == 4)
    }

    @Test(
        "Signing intent cannot cross the deadline into a BCH signature",
        .timeLimit(.minutes(1))
    )
    func expireDuringSigningIntentPersistence() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 2,
            suspensionProbe: suspension
        )
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let clock = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe,
            currentDate: { clock.withLock { $0 } }
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let finalization = Task {
            try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        await suspension.waitUntilSuspended()
        clock.withLock { $0 = lease.expiresAt }
        await suspension.resume()

        await #expect(throws: OpalBase.Account.MosaicHostFailure.reservationExpired) {
            _ = try await finalization.value
        }
        #expect(await fixture.host.readSigningInvocationCount() == 0)
        #expect(await journalProbe.readRecords().count == 3)
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            try await fixture.host.releaseMosaicReservation(lease.reference)
        }
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: request)
        }
    }

    @Test(
        "Cancellation after signing intent cannot produce a BCH signature",
        .timeLimit(.minutes(1))
    )
    func cancelDuringSigningIntentPersistence() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 2,
            suspensionProbe: suspension
        )
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let finalization = Task {
            try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        await suspension.waitUntilSuspended()
        finalization.cancel()
        await suspension.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await finalization.value
        }
        #expect(await fixture.host.readSigningInvocationCount() == 0)
        #expect(await journalProbe.readRecords().count == 3)
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            try await fixture.host.releaseMosaicReservation(lease.reference)
        }
    }

    @Test(
        "Commit waits for durable locally signed state",
        .timeLimit(.minutes(1))
    )
    func blockCommitDuringLocallySignedPersistence() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 3,
            suspensionProbe: suspension
        )
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let firstFinalization = Task {
            try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        await suspension.waitUntilSuspended()
        let unsigned = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: request.unsignedTransactionBytes
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.finalizationRequired) {
            try await fixture.host.commitMosaicReservation(
                lease.reference,
                completeTransaction: unsigned
            )
        }
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            try await fixture.host.releaseMosaicReservation(lease.reference)
        }
        #expect(await journalProbe.readRecords().count == 3)

        await suspension.resume()
        let finalized = try await firstFinalization.value
        let complete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: finalized.signedFusionTransactionBytes
        )
        try await fixture.host.commitMosaicReservation(
            lease.reference,
            completeTransaction: complete
        )
        #expect(await journalProbe.readRecords().count == 6)
    }

    @Test(
        "Commit intent pins exact bytes before suspension",
        .timeLimit(.minutes(1))
    )
    func pinCommitBytesBeforeJournalSuspension() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 4,
            suspensionProbe: suspension
        )
        let prepared = try await makeFinalizedAttempt(journalProbe: journalProbe)
        let firstCommit = Task {
            try await prepared.fixture.host.commitMosaicReservation(
                prepared.lease.reference,
                completeTransaction: prepared.complete
            )
        }
        await suspension.waitUntilSuspended()

        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            try await prepared.fixture.host.commitMosaicReservation(
                prepared.lease.reference,
                completeTransaction: prepared.complete
            )
        }
        let conflicting = try makeConflictingCompleteTransaction(prepared.complete)
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure.conflictingCompleteTransaction
        ) {
            try await prepared.fixture.host.commitMosaicReservation(
                prepared.lease.reference,
                completeTransaction: conflicting
            )
        }
        await #expect(throws: OpalBase.Account.MosaicHostFailure.terminalReservation) {
            try await prepared.fixture.host.releaseMosaicReservation(prepared.lease.reference)
        }

        await suspension.resume()
        try await firstCommit.value
        let records = await journalProbe.readRecords()
        #expect(records.count == 6)
        if case .commitIntent(_, let transaction) = records[4] {
            #expect(transaction == prepared.complete)
        } else {
            Issue.record("Expected one pinned commit intent")
        }
        if case .committed(_, let transaction) = records[5] {
            #expect(transaction == prepared.complete)
        } else {
            Issue.record("Expected one committed transaction")
        }
    }

    @Test(
        "Release intent serializes cleanup and terminal callbacks",
        .timeLimit(.minutes(1))
    )
    func serializeReleaseDuringJournalSuspension() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 2,
            suspensionProbe: suspension
        )
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let lease = try await fixture.reserve()
        let firstRelease = Task {
            try await fixture.host.releaseMosaicReservation(lease.reference)
        }
        await suspension.waitUntilSuspended()

        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            try await fixture.host.releaseMosaicReservation(lease.reference)
        }
        await #expect(throws: OpalBase.Account.MosaicHostFailure.terminalReservation) {
            _ = try await fixture.host.finalizeMosaicTransaction(
                for: fixture.makeSigningRequest(lease: lease)
            )
        }
        await #expect(throws: OpalBase.Account.MosaicHostFailure.terminalReservation) {
            _ = try await fixture.reserve()
        }

        await suspension.resume()
        try await firstRelease.value
        try await fixture.host.releaseMosaicReservation(lease.reference)
        #expect(await journalProbe.readRecords().count == 4)
    }

    @Test(
        "Scheduled expiry does not cancel its terminal journal append",
        .timeLimit(.minutes(1))
    )
    func preserveScheduledExpiryJournalCompletion() async throws {
        let expirationProbe = MosaicExpirationProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            cancellationSensitiveAppendIndices: [3]
        )
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe,
            sleepUntilDate: { _ in await expirationProbe.wait() }
        )
        let lease = try await fixture.reserve()

        await expirationProbe.release()
        let wasCancelled = await journalProbe.waitForCancellationObservation(
            atAppendIndex: 3
        )
        #expect(!wasCancelled)
        let records = await journalProbe.readRecords()
        #expect(records.count == 4)
        if case .released(let reference) = records[3] {
            #expect(reference == lease.reference)
        } else {
            Issue.record("Expected scheduled expiry to persist terminal release")
        }
    }

    @Test(
        "Broadcast pins exact bytes and permits one active network call",
        .timeLimit(.minutes(1))
    )
    func serializeBroadcastDuringIntentSuspension() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 6,
            suspensionProbe: suspension
        )
        let prepared = try await makeFinalizedAttempt(journalProbe: journalProbe)
        try await prepared.fixture.host.commitMosaicReservation(
            prepared.lease.reference,
            completeTransaction: prepared.complete
        )
        let broadcastProbe = MosaicBroadcastProbeActor(journalProbe: journalProbe)
        let coordinator = OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            reservationReference: prepared.lease.reference,
            journal: journalProbe.makeJournal(),
            transactionClient: broadcastProbe.makeClient()
        )
        let firstBroadcast = Task {
            try await coordinator.broadcast(prepared.complete)
        }
        await suspension.waitUntilSuspended()

        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            _ = try await coordinator.broadcast(prepared.complete)
        }
        let conflicting = try makeConflictingCompleteTransaction(prepared.complete)
        await #expect(throws: OpalBase.Account.MosaicHostFailure.conflictingBroadcast) {
            _ = try await coordinator.broadcast(conflicting)
        }

        await suspension.resume()
        let hash = try await firstBroadcast.value
        let duplicateHash = try await coordinator.broadcast(prepared.complete)
        #expect(duplicateHash == hash)
        #expect(await broadcastProbe.readBroadcasts().count == 1)
        #expect(await journalProbe.readRecords().count == 8)
    }

    @Test(
        "Cancellation after broadcast intent cannot reach network I/O",
        .timeLimit(.minutes(1))
    )
    func cancelAfterBroadcastIntentPersistence() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 6,
            suspensionProbe: suspension
        )
        let prepared = try await makeFinalizedAttempt(journalProbe: journalProbe)
        try await prepared.fixture.host.commitMosaicReservation(
            prepared.lease.reference,
            completeTransaction: prepared.complete
        )
        let broadcastProbe = MosaicBroadcastProbeActor(journalProbe: journalProbe)
        let coordinator = OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            reservationReference: prepared.lease.reference,
            journal: journalProbe.makeJournal(),
            transactionClient: broadcastProbe.makeClient()
        )
        let broadcast = Task {
            try await coordinator.broadcast(prepared.complete)
        }
        await suspension.waitUntilSuspended()
        broadcast.cancel()
        await suspension.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await broadcast.value
        }
        #expect(await broadcastProbe.readBroadcasts().isEmpty)
        let interruptedRecords = await journalProbe.readRecords()
        #expect(interruptedRecords.count == 7)
        #expect(
            try OpalBase.Account.MosaicAttemptRecoveryPlanner.plan(for: interruptedRecords)
                == .broadcast(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete
                )
        )

        _ = try await coordinator.broadcast(prepared.complete)
        #expect(await broadcastProbe.readBroadcasts().count == 1)
        #expect(await journalProbe.readRecords().count == 8)
    }

    @Test("Ambiguous intent failures retain exact operation pins")
    func retainExactPinsAfterIntentPersistenceFailures() async throws {
        try await verifyReservationIntentFailurePin()
        try await verifyCommitIntentFailurePin()
        try await verifyBroadcastIntentFailurePin()
    }
}

private extension AccountMosaicTransactionHostValidator {
    func makeReplacementReservationRequest(
        for fixture: MosaicHostFixture
    ) throws -> OpalFusion.Host.MosaicReservationRequest {
        let request = fixture.reservationRequest
        return try .init(
            attemptIdentifier: [0x12],
            networkGenesisHash: request.networkGenesisHash,
            roundIdentifier: Array(repeating: 0x34, count: 32),
            expiresAt: request.expiresAt,
            componentCount: request.componentCount,
            feeRateSatoshisPerByte: request.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: request.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: request.maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: request.requiredExcessFeeSatoshis,
            transactionProfileIdentifier: request.transactionProfileIdentifier
        )
    }

    func makeFinalizedAttempt(
        journalProbe: MosaicAttemptJournalProbeActor
    ) async throws -> (
        fixture: MosaicHostFixture,
        lease: OpalFusion.Host.MosaicReservationLease,
        complete: OpalFusion.Host.MosaicCompleteTransaction
    ) {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let lease = try await fixture.reserve()
        let finalized = try await fixture.host.finalizeMosaicTransaction(
            for: fixture.makeSigningRequest(lease: lease)
        )
        let complete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: finalized.signedFusionTransactionBytes
        )
        return (fixture, lease, complete)
    }

    func makeConflictingCompleteTransaction(
        _ transaction: OpalFusion.Host.MosaicCompleteTransaction
    ) throws -> OpalFusion.Host.MosaicCompleteTransaction {
        var bytes = transaction.transactionBytes
        bytes[bytes.index(before: bytes.endIndex)] ^= 0x01
        return try .init(transactionBytes: bytes)
    }

    func verifyReservationIntentFailurePin() async throws {
        let journalProbe = MosaicAttemptJournalProbeActor(failingAppendIndices: [0])
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.journalPersistenceFailed) {
            _ = try await fixture.reserve()
        }
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            _ = try await fixture.reserve()
        }
        let replacement = try makeReplacementReservationRequest(for: fixture)
        await #expect(throws: OpalBase.Account.MosaicHostFailure.inPlaceRetryNotPermitted) {
            _ = try await fixture.host.reserveMosaicContribution(for: replacement)
        }
        #expect(await journalProbe.readRecords().isEmpty)
        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
    }

    func verifyCommitIntentFailurePin() async throws {
        let journalProbe = MosaicAttemptJournalProbeActor(failingAppendIndices: [4])
        let prepared = try await makeFinalizedAttempt(journalProbe: journalProbe)

        await #expect(throws: OpalBase.Account.MosaicHostFailure.journalPersistenceFailed) {
            try await prepared.fixture.host.commitMosaicReservation(
                prepared.lease.reference,
                completeTransaction: prepared.complete
            )
        }
        let conflicting = try makeConflictingCompleteTransaction(prepared.complete)
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure.conflictingCompleteTransaction
        ) {
            try await prepared.fixture.host.commitMosaicReservation(
                prepared.lease.reference,
                completeTransaction: conflicting
            )
        }
        try await prepared.fixture.host.commitMosaicReservation(
            prepared.lease.reference,
            completeTransaction: prepared.complete
        )
        #expect(await journalProbe.readRecords().count == 6)
    }

    func verifyBroadcastIntentFailurePin() async throws {
        let journalProbe = MosaicAttemptJournalProbeActor(failingAppendIndices: [6])
        let prepared = try await makeFinalizedAttempt(journalProbe: journalProbe)
        try await prepared.fixture.host.commitMosaicReservation(
            prepared.lease.reference,
            completeTransaction: prepared.complete
        )
        let broadcastProbe = MosaicBroadcastProbeActor(journalProbe: journalProbe)
        let coordinator = OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            reservationReference: prepared.lease.reference,
            journal: journalProbe.makeJournal(),
            transactionClient: broadcastProbe.makeClient()
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.journalPersistenceFailed) {
            _ = try await coordinator.broadcast(prepared.complete)
        }
        let conflicting = try makeConflictingCompleteTransaction(prepared.complete)
        await #expect(throws: OpalBase.Account.MosaicHostFailure.conflictingBroadcast) {
            _ = try await coordinator.broadcast(conflicting)
        }
        _ = try await coordinator.broadcast(prepared.complete)
        #expect(await broadcastProbe.readBroadcasts().count == 1)
        #expect(await journalProbe.readRecords().count == 8)
    }
}
#endif
