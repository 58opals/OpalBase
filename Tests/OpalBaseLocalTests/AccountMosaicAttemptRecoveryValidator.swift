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

    @Test("Persist broadcast intent before I/O and retry only exact bytes")
    func persistBroadcastIntentBeforeIO() async throws {
        let prepared = try await makeCommittedAttempt()
        let broadcastProbe = MosaicBroadcastProbeActor(
            journalProbe: prepared.fixture.journalProbe,
            failuresRemaining: 1
        )
        let approvalProbe = MosaicBroadcastApprovalProbeActor()
        let coordinator = try OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            candidate: prepared.candidate,
            expectedNetwork: prepared.fixture.network,
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(),
            requestApproval: approvalProbe.makeRequester()
        )

        await #expect(throws: MosaicBroadcastProbeFailure.scripted) {
            _ = try await coordinator.broadcast()
        }
        #expect(await broadcastProbe.readObservedPersistedIntent())
        #expect(
            try Planner.plan(
                for: await prepared.fixture.journalProbe.readRecords()
            ) == .resumeApprovedBroadcast(
                reference: prepared.lease.reference,
                transaction: prepared.complete,
                broadcastIntentPersisted: true
            )
        )

        let hash = try await coordinator.broadcast()
        let duplicateHash = try await coordinator.broadcast()
        #expect(hash == duplicateHash)
        #expect(await approvalProbe.readRequests().count == 1)
        #expect(await broadcastProbe.readBroadcasts().count == 2)
        let completedRecords = await prepared.fixture.journalProbe.readRecords()
        #expect(
            try Planner.plan(for: completedRecords) == .complete(hash)
        )
        let gate = OpalBase.Account.MosaicAttemptRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journal: prepared.fixture.journalProbe.makeJournal()
        )
        let recoveryOutcome = try await gate.restoreInputQuarantineAndPlan(
            from: completedRecords
        )
        guard case let .chainReconciliationRequired(recoveredHash)
                = recoveryOutcome else {
            Issue.record("Expected chain reconciliation after accepted broadcast")
            return
        }
        #expect(recoveredHash == hash)
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
            failingAppendIndices: [8]
        )
        let prepared = try await makeCommittedAttempt(journalProbe: journalProbe)
        let broadcastProbe = MosaicBroadcastProbeActor(journalProbe: journalProbe)
        let approvalProbe = MosaicBroadcastApprovalProbeActor()
        let coordinator = try OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            candidate: prepared.candidate,
            expectedNetwork: prepared.fixture.network,
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(),
            requestApproval: approvalProbe.makeRequester()
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.journalPersistenceFailed) {
            _ = try await coordinator.broadcast()
        }
        #expect(await broadcastProbe.readBroadcasts().count == 1)
        #expect(await approvalProbe.readRequests().count == 1)
        #expect(
            try Planner.plan(for: await journalProbe.readRecords())
                == .resumeApprovedBroadcast(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete,
                    broadcastIntentPersisted: true
                )
        )

        let hash = try await coordinator.broadcast()
        #expect(await broadcastProbe.readBroadcasts().count == 2)
        #expect(await approvalProbe.readRequests().count == 1)
        #expect(
            try Planner.plan(for: await journalProbe.readRecords())
                == .complete(hash)
        )
    }

    @Test("Broadcast requires app approval and an exact committed candidate")
    func requireApprovalAndCommittedAuthority() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let uncommittedFixture = try await MosaicHostFixture.make(
            transactionPolicy: policy
        )
        _ = try await uncommittedFixture.reserve()
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .broadcastCandidateUnavailable
        ) {
            _ = try await uncommittedFixture.host
                .makeCommittedBroadcastCandidate()
        }

        let prepared = try await makeCommittedAttempt()
        let broadcastProbe = MosaicBroadcastProbeActor(
            journalProbe: prepared.fixture.journalProbe
        )
        let approvalProbe = MosaicBroadcastApprovalProbeActor(
            decisions: [.rejected, .approved]
        )
        let coordinator = try OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            candidate: prepared.candidate,
            expectedNetwork: prepared.fixture.network,
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(),
            requestApproval: approvalProbe.makeRequester()
        )

        await #expect(
            throws: OpalBase.Account.MosaicHostFailure.broadcastNotApproved
        ) {
            _ = try await coordinator.broadcast()
        }
        #expect(await prepared.fixture.journalProbe.readRecords().count == 6)
        #expect(await broadcastProbe.readBroadcasts().isEmpty)

        _ = try await coordinator.broadcast()
        let requests = await approvalProbe.readRequests()
        #expect(requests.count == 2)
        #expect(requests.allSatisfy {
            $0.reservationRequest == prepared.fixture.reservationRequest
                && $0.reservationReference == prepared.lease.reference
                && $0.completeTransaction == prepared.complete
                && $0.profile == prepared.fixture.profile
                && $0.network == prepared.fixture.network
        })
        #expect(await broadcastProbe.readBroadcasts().count == 1)

        #expect(throws: OpalBase.WalletSecurityProfile.Error.broadcastUnavailable(
            networkAccess: .publicChainSync
        )) {
            _ = try OpalBase.Account.MosaicTransactionBroadcastCoordinator(
                candidate: prepared.candidate,
                expectedNetwork: prepared.fixture.network,
                securityProfile: .init(
                    secretPersistencePolicy: .acceptProviderOutput,
                    networkAccess: .publicChainSync,
                    signingAccess: .inProcess
                ),
                transactionClient: broadcastProbe.makeClient(),
                requestApproval: MosaicBroadcastApprovalTestSupport.approve
            )
        }
        #expect(throws: OpalBase.Account.MosaicHostFailure.invalidNetworkBinding) {
            _ = try OpalBase.Account.MosaicTransactionBroadcastCoordinator(
                candidate: prepared.candidate,
                expectedNetwork: .mainnet,
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                transactionClient: broadcastProbe.makeClient(),
                requestApproval: MosaicBroadcastApprovalTestSupport.approve
            )
        }
    }

    @Test(
        "Cancellation during approval cannot persist intent or reach network",
        .timeLimit(.minutes(1))
    )
    func cancelDuringBroadcastApproval() async throws {
        let prepared = try await makeCommittedAttempt()
        let suspension = MosaicOperationSuspensionProbeActor()
        let approvalProbe = MosaicBroadcastApprovalProbeActor(
            decisions: [.approved, .approved],
            suspensionProbe: suspension
        )
        let broadcastProbe = MosaicBroadcastProbeActor(
            journalProbe: prepared.fixture.journalProbe
        )
        let coordinator = try OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            candidate: prepared.candidate,
            expectedNetwork: prepared.fixture.network,
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(),
            requestApproval: approvalProbe.makeRequester()
        )
        let broadcast = Task {
            try await coordinator.broadcast()
        }
        await suspension.waitUntilSuspended()
        broadcast.cancel()
        await suspension.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await broadcast.value
        }
        #expect(await prepared.fixture.journalProbe.readRecords().count == 6)
        #expect(await broadcastProbe.readBroadcasts().isEmpty)

        _ = try await coordinator.broadcast()
        #expect(await approvalProbe.readRequests().count == 2)
        #expect(await broadcastProbe.readBroadcasts().count == 1)
    }

    @Test(
        "Cancellation during durable approval persistence requires fresh approval",
        .timeLimit(.minutes(1))
    )
    func cancelDuringBroadcastApprovalPersistence() async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let journalProbe = MosaicAttemptJournalProbeActor(
            suspendedAppendIndex: 6,
            suspensionProbe: suspension,
            cancellationSensitiveAppendIndices: [6]
        )
        let prepared = try await makeCommittedAttempt(journalProbe: journalProbe)
        let approvalProbe = MosaicBroadcastApprovalProbeActor(
            decisions: [.approved, .approved]
        )
        let broadcastProbe = MosaicBroadcastProbeActor(journalProbe: journalProbe)
        let coordinator = try OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            candidate: prepared.candidate,
            expectedNetwork: prepared.fixture.network,
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(),
            requestApproval: approvalProbe.makeRequester()
        )

        let broadcast = Task {
            try await coordinator.broadcast()
        }
        await suspension.waitUntilSuspended()
        broadcast.cancel()
        await suspension.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await broadcast.value
        }
        #expect(await journalProbe.readRecords().count == 6)
        #expect(await broadcastProbe.readBroadcasts().isEmpty)

        _ = try await coordinator.broadcast()
        #expect(await approvalProbe.readRequests().count == 2)
        #expect(await broadcastProbe.readBroadcasts().count == 1)
        #expect(await journalProbe.readRecords().count == 9)
    }

    @Test("Approval provider failures stop before journal or network I/O")
    func rejectApprovalProviderFailure() async throws {
        let prepared = try await makeCommittedAttempt()
        let broadcastProbe = MosaicBroadcastProbeActor(
            journalProbe: prepared.fixture.journalProbe
        )
        let coordinator = try OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            candidate: prepared.candidate,
            expectedNetwork: prepared.fixture.network,
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(),
            requestApproval: { _ in
                throw MosaicBroadcastProbeFailure.scripted
            }
        )

        await #expect(
            throws: OpalBase.Account.MosaicHostFailure.broadcastNotApproved
        ) {
            _ = try await coordinator.broadcast()
        }
        #expect(await prepared.fixture.journalProbe.readRecords().count == 6)
        #expect(await broadcastProbe.readBroadcasts().isEmpty)
    }

    @Test("A legacy broadcast intent still requires fresh durable approval")
    func requireApprovalForLegacyBroadcastIntent() async throws {
        let prepared = try await makeCommittedAttempt()
        try await prepared.fixture.journalProbe.makeJournal().append(
            .broadcastIntent(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        )
        let interruptedRecords = await prepared.fixture.journalProbe.readRecords()
        #expect(
            try Planner.plan(for: interruptedRecords)
                == .broadcastApprovalRequired(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete,
                    broadcastIntentPersisted: true
                )
        )

        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        let gate = OpalBase.Account.MosaicAttemptRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journal: prepared.fixture.journalProbe.makeJournal()
        )
        let outcome = try await gate.restoreInputQuarantineAndPlan(
            from: interruptedRecords
        )
        guard case let .broadcastApprovalRequired(candidate) = outcome else {
            Issue.record("Expected fresh approval for the legacy broadcast intent")
            return
        }
        #expect(!candidate.approvalPersisted)
        #expect(candidate.broadcastIntentPersisted)

        let approvalProbe = MosaicBroadcastApprovalProbeActor()
        let broadcastProbe = MosaicBroadcastProbeActor(
            journalProbe: prepared.fixture.journalProbe
        )
        let coordinator = try OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            candidate: candidate,
            expectedNetwork: prepared.fixture.network,
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(),
            requestApproval: approvalProbe.makeRequester()
        )

        let hash = try await coordinator.broadcast()
        #expect(await approvalProbe.readRequests().count == 1)
        #expect(await broadcastProbe.readBroadcasts().count == 1)
        #expect(await prepared.fixture.journalProbe.readRecords().count == 9)
        #expect(
            try Planner.plan(
                for: await prepared.fixture.journalProbe.readRecords()
            ) == .complete(hash)
        )
    }

    @Test("Recovered durable approval persists intent before network I/O")
    func resumeApprovalCheckpointInFreshCoordinator() async throws {
        let prepared = try await makeCommittedAttempt()
        try await prepared.fixture.journalProbe.makeJournal().append(
            .broadcastApproved(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        )
        let approvedRecords = await prepared.fixture.journalProbe.readRecords()
        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        let gate = OpalBase.Account.MosaicAttemptRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journal: prepared.fixture.journalProbe.makeJournal()
        )
        let outcome = try await gate.restoreInputQuarantineAndPlan(
            from: approvedRecords
        )
        guard case let .resumeApprovedBroadcast(candidate) = outcome else {
            Issue.record("Expected a durable-approval recovery candidate")
            return
        }
        #expect(candidate.approvalPersisted)
        #expect(!candidate.broadcastIntentPersisted)

        let approvalProbe = MosaicBroadcastApprovalProbeActor(
            decisions: [.rejected]
        )
        let broadcastProbe = MosaicBroadcastProbeActor(
            journalProbe: prepared.fixture.journalProbe
        )
        let coordinator = try OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            candidate: candidate,
            expectedNetwork: prepared.fixture.network,
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(),
            requestApproval: approvalProbe.makeRequester()
        )

        let hash = try await coordinator.broadcast()
        #expect(await approvalProbe.readRequests().isEmpty)
        #expect(await broadcastProbe.readObservedPersistedIntent())
        #expect(await broadcastProbe.readBroadcasts().count == 1)
        #expect(await prepared.fixture.journalProbe.readRecords().count == 9)
        #expect(
            try Planner.plan(
                for: await prepared.fixture.journalProbe.readRecords()
            ) == .complete(hash)
        )
    }

    @Test("Recovered approved intent retries exact bytes without new approval")
    func resumeApprovedIntentInFreshCoordinator() async throws {
        let prepared = try await makeCommittedAttempt()
        let failingBroadcast = MosaicBroadcastProbeActor(
            journalProbe: prepared.fixture.journalProbe,
            failuresRemaining: 1
        )
        let firstApproval = MosaicBroadcastApprovalProbeActor()
        let firstCoordinator = try OpalBase.Account
            .MosaicTransactionBroadcastCoordinator(
                candidate: prepared.candidate,
                expectedNetwork: prepared.fixture.network,
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                transactionClient: failingBroadcast.makeClient(),
                requestApproval: firstApproval.makeRequester()
            )
        await #expect(throws: MosaicBroadcastProbeFailure.scripted) {
            _ = try await firstCoordinator.broadcast()
        }

        let interruptedRecords = await prepared.fixture.journalProbe.readRecords()
        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        let recoveryGate = OpalBase.Account.MosaicAttemptRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journal: prepared.fixture.journalProbe.makeJournal()
        )
        let recoveryOutcome = try await recoveryGate
            .restoreInputQuarantineAndPlan(from: interruptedRecords)
        guard case let .resumeApprovedBroadcast(recoveredCandidate)
                = recoveryOutcome else {
            Issue.record("Expected an approved exact-broadcast recovery candidate")
            return
        }
        #expect(recoveredCandidate.approvalPersisted)
        #expect(recoveredCandidate.broadcastIntentPersisted)
        let recoveredApproval = MosaicBroadcastApprovalProbeActor(
            decisions: [.rejected]
        )
        let recoveredBroadcast = MosaicBroadcastProbeActor(
            journalProbe: prepared.fixture.journalProbe
        )
        let recoveredCoordinator = try OpalBase.Account
            .MosaicTransactionBroadcastCoordinator(
                candidate: recoveredCandidate,
                expectedNetwork: prepared.fixture.network,
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                transactionClient: recoveredBroadcast.makeClient(),
                requestApproval: recoveredApproval.makeRequester()
            )

        _ = try await recoveredCoordinator.broadcast()
        #expect(await recoveredApproval.readRequests().isEmpty)
        #expect(await recoveredBroadcast.readBroadcasts().count == 1)
    }

    @Test("Startup recovery re-quarantines exact journaled inputs")
    func quarantineRestoredInputsBeforeRecoveryAction() async throws {
        let prepared = try await makeCommittedAttempt()
        let records = await prepared.fixture.journalProbe.readRecords()
        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        #expect(
            await prepared.fixture.addressBook.listSpendableUTXOs()
                .contains(prepared.fixture.selectedInput)
        )

        let gate = OpalBase.Account.MosaicAttemptRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journal: prepared.fixture.journalProbe.makeJournal()
        )
        let candidateOutcome = try await gate.restoreInputQuarantineAndPlan(
            from: records
        )
        guard case let .broadcastApprovalRequired(candidate) = candidateOutcome else {
            Issue.record("Expected a broadcast-approval candidate")
            return
        }
        #expect(candidate.reservationRequest == prepared.fixture.reservationRequest)
        #expect(candidate.reservationReference == prepared.lease.reference)
        #expect(candidate.completeTransaction == prepared.complete)
        #expect(!candidate.approvalPersisted)
        #expect(!candidate.broadcastIntentPersisted)
        #expect(
            !(await prepared.fixture.addressBook.listSpendableUTXOs())
                .contains(prepared.fixture.selectedInput)
        )

        await prepared.fixture.addressBook.releaseUTXOs(
            Set([prepared.fixture.selectedInput])
        )
        let signingOutcome = try await gate.restoreInputQuarantineAndPlan(
            from: Array(records.prefix(3))
        )
        guard case let .walletReconciliationRequired(signingPlan)
                = signingOutcome else {
            Issue.record("Expected signing reconciliation")
            return
        }
        #expect(
            signingPlan == .reconcileSigningIntent(
                reference: prepared.lease.reference,
                request: prepared.request
            )
        )
        #expect(
            !(await prepared.fixture.addressBook.listSpendableUTXOs())
                .contains(prepared.fixture.selectedInput)
        )
    }

    @Test("Recovery blocks missing inputs and rejects payload substitution")
    func validateRecoveredSelectedInputPayload() async throws {
        let prepared = try await makeCommittedAttempt()
        let records = await prepared.fixture.journalProbe.readRecords()
        let gate = OpalBase.Account.MosaicAttemptRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journal: prepared.fixture.journalProbe.makeJournal()
        )

        let missingInputOutcome = try await gate.restoreInputQuarantineAndPlan(
            from: records
        )
        guard case let .walletReconciliationRequired(missingInputPlan)
                = missingInputOutcome else {
            Issue.record("Expected missing-input reconciliation")
            return
        }
        #expect(
            missingInputPlan == .broadcastApprovalRequired(
                reference: prepared.lease.reference,
                transaction: prepared.complete,
                broadcastIntentPersisted: false
            )
        )

        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        let substitutedInput = OpalBase.Transaction.Output.Unspent(
            value: prepared.fixture.selectedInput.value + 1,
            lockingScript: prepared.fixture.selectedInput.lockingScript,
            previousTransactionHash:
                prepared.fixture.selectedInput.previousTransactionHash,
            previousTransactionOutputIndex:
                prepared.fixture.selectedInput.previousTransactionOutputIndex
        )
        guard case let .reservationIntent(
            reference,
            request,
            _,
            outputAmountsSatoshis
        ) = records[0] else {
            Issue.record("Expected reservation intent")
            return
        }
        var substitutedRecords = records
        substitutedRecords[0] = .reservationIntent(
            reference: reference,
            request: request,
            selectedInputs: [.init(substitutedInput)],
            outputAmountsSatoshis: outputAmountsSatoshis
        )
        await #expect(
            throws: OpalBase.Account.MosaicAttemptRecoveryGate.Failure
                .selectedInputMismatch
        ) {
            _ = try await gate.restoreInputQuarantineAndPlan(
                from: substitutedRecords
            )
        }
    }

    @Test("Recovery rejects invalid journals, inputs, and broadcast candidates")
    func rejectInvalidRecoveryAuthority() async throws {
        let prepared = try await makeCommittedAttempt()
        let records = await prepared.fixture.journalProbe.readRecords()
        let gate = OpalBase.Account.MosaicAttemptRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journal: prepared.fixture.journalProbe.makeJournal()
        )

        await #expect(
            throws: OpalBase.Account.MosaicAttemptRecoveryGate.Failure
                .invalidJournal(.invalidTransition)
        ) {
            _ = try await gate.restoreInputQuarantineAndPlan(
                from: [records[0], records[4]]
            )
        }

        guard case let .reservationIntent(
            reference,
            request,
            selectedInputs,
            outputAmountsSatoshis
        ) = records[0] else {
            Issue.record("Expected reservation intent")
            return
        }
        var duplicateInputRecords = records
        duplicateInputRecords[0] = .reservationIntent(
            reference: reference,
            request: request,
            selectedInputs: selectedInputs + selectedInputs,
            outputAmountsSatoshis: outputAmountsSatoshis
        )
        await #expect(
            throws: OpalBase.Account.MosaicAttemptRecoveryGate.Failure
                .invalidSelectedInput
        ) {
            _ = try await gate.restoreInputQuarantineAndPlan(
                from: duplicateInputRecords
            )
        }

        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        let futureVersionRequest = try OpalFusion.Host.MosaicReservationRequest(
            attemptIdentifier: request.attemptIdentifier,
            networkGenesisHash: request.networkGenesisHash,
            roundIdentifier: request.roundIdentifier,
            expiresAt: request.expiresAt,
            componentCount: request.componentCount,
            feeRateSatoshisPerByte: request.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: request.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: request.maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: request.requiredExcessFeeSatoshis,
            transactionProfileIdentifier:
                "bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.5"
        )
        var futureVersionRecords = records
        futureVersionRecords[0] = .reservationIntent(
            reference: reference,
            request: futureVersionRequest,
            selectedInputs: selectedInputs,
            outputAmountsSatoshis: outputAmountsSatoshis
        )
        await #expect(
            throws: OpalBase.Account.MosaicAttemptRecoveryGate.Failure
                .invalidBroadcastCandidate
        ) {
            _ = try await gate.restoreInputQuarantineAndPlan(
                from: futureVersionRecords
            )
        }
        #expect(
            !(await prepared.fixture.addressBook.listSpendableUTXOs())
                .contains(prepared.fixture.selectedInput)
        )
    }

    @Test("Terminal release and empty recovery do not quarantine spendable inputs")
    func leaveTerminalOrUnstartedWalletStateUntouched() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(transactionPolicy: policy)
        let gate = OpalBase.Account.MosaicAttemptRecoveryGate(
            addressBook: fixture.addressBook,
            journal: fixture.journalProbe.makeJournal()
        )
        let emptyOutcome = try await gate.restoreInputQuarantineAndPlan(from: [])
        guard case .noAction = emptyOutcome else {
            Issue.record("Expected no recovery action")
            return
        }
        #expect(
            await fixture.addressBook.listSpendableUTXOs()
                .contains(fixture.selectedInput)
        )

        let lease = try await fixture.reserve()
        try await fixture.host.releaseMosaicReservation(lease.reference)
        let releasedOutcome = try await gate.restoreInputQuarantineAndPlan(
            from: await fixture.journalProbe.readRecords()
        )
        guard case .released = releasedOutcome else {
            Issue.record("Expected terminal release recovery")
            return
        }
        #expect(
            await fixture.addressBook.listSpendableUTXOs()
                .contains(fixture.selectedInput)
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

    private func makeCommittedAttempt(
        journalProbe: MosaicAttemptJournalProbeActor = .init()
    ) async throws -> (
        fixture: MosaicHostFixture,
        lease: OpalFusion.Host.MosaicReservationLease,
        request: OpalFusion.Host.MosaicTransactionSigningRequest,
        finalized: OpalFusion.Host.FinalizedTransaction,
        complete: OpalFusion.Host.MosaicCompleteTransaction,
        candidate: OpalBase.Account.MosaicCommittedBroadcastCandidate
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
        let candidate = try await fixture.host.makeCommittedBroadcastCandidate()
        return (fixture, lease, request, finalized, complete, candidate)
    }
}
#endif
