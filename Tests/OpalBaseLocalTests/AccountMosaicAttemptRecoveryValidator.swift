// AccountMosaicAttemptRecoveryValidator.swift

#if os(macOS)
import CryptoKit
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
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(
                testingNetwork: prepared.fixture.network
            ),
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
        let gate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let recoveryOutcome = try await gate.restoreInputQuarantineAndPlan()
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
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(
                testingNetwork: prepared.fixture.network
            ),
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
        let independentlyRequestedCandidate = try await prepared.fixture.host
            .makeCommittedBroadcastCandidate()
        let coordinator = try OpalBase.Account.MosaicTransactionBroadcastCoordinator(
            candidate: prepared.candidate,
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(
                testingNetwork: prepared.fixture.network
            ),
            requestApproval: approvalProbe.makeRequester()
        )
        #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .broadcastCandidateUnavailable
        ) {
            _ = try OpalBase.Account.MosaicTransactionBroadcastCoordinator(
                candidate: independentlyRequestedCandidate,
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                transactionClient: broadcastProbe.makeClient(
                    testingNetwork: prepared.fixture.network
                ),
                requestApproval: MosaicBroadcastApprovalTestSupport.approve
            )
        }

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
                securityProfile: .init(
                    secretPersistencePolicy: .acceptProviderOutput,
                    networkAccess: .publicChainSync,
                    signingAccess: .inProcess
                ),
                transactionClient: broadcastProbe.makeClient(
                    testingNetwork: prepared.fixture.network
                ),
                requestApproval: MosaicBroadcastApprovalTestSupport.approve
            )
        }
        #expect(throws: OpalBase.Account.MosaicHostFailure.invalidNetworkBinding) {
            _ = try OpalBase.Account.MosaicTransactionBroadcastCoordinator(
                candidate: prepared.candidate,
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                transactionClient: broadcastProbe.makeClient(
                    testingNetwork: .mainnet
                ),
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
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(
                testingNetwork: prepared.fixture.network
            ),
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
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(
                testingNetwork: prepared.fixture.network
            ),
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
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(
                testingNetwork: prepared.fixture.network
            ),
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
        try await prepared.candidate.journal.append(
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
        let gate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let outcome = try await gate.restoreInputQuarantineAndPlan()
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
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(
                testingNetwork: prepared.fixture.network
            ),
            requestApproval: approvalProbe.makeRequester()
        )

        let hash = try await coordinator.broadcast()
        #expect(await approvalProbe.readRequests().count == 1)
        #expect(await broadcastProbe.readBroadcasts().count == 1)
        #expect(await prepared.fixture.journalProbe.readRecords().count == 10)
        #expect(
            try Planner.plan(
                for: await prepared.fixture.journalProbe.readRecords()
            ) == .complete(hash)
        )
    }

    @Test("Recovered durable approval persists intent before network I/O")
    func resumeApprovalCheckpointInFreshCoordinator() async throws {
        let prepared = try await makeCommittedAttempt()
        try await prepared.candidate.journal.append(
            .broadcastApproved(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        )
        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        let gate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let outcome = try await gate.restoreInputQuarantineAndPlan()
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
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            transactionClient: broadcastProbe.makeClient(
                testingNetwork: prepared.fixture.network
            ),
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
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                transactionClient: failingBroadcast.makeClient(
                    testingNetwork: prepared.fixture.network
                ),
                requestApproval: firstApproval.makeRequester()
            )
        await #expect(throws: MosaicBroadcastProbeFailure.scripted) {
            _ = try await firstCoordinator.broadcast()
        }

        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        let recoveryGate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let recoveryOutcome = try await recoveryGate
            .restoreInputQuarantineAndPlan()
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
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                transactionClient: recoveredBroadcast.makeClient(
                    testingNetwork: prepared.fixture.network
                ),
                requestApproval: recoveredApproval.makeRequester()
            )

        _ = try await recoveredCoordinator.broadcast()
        #expect(await recoveredApproval.readRequests().isEmpty)
        #expect(await recoveredBroadcast.readBroadcasts().count == 1)
    }

    @Test("Stale recovery owner cannot reach network I/O")
    func rejectStaleRecoveryOwnerBeforeBroadcast() async throws {
        let prepared = try await makeCommittedAttempt()
        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)

        let firstGate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let secondGate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let firstOutcome = try await firstGate.restoreInputQuarantineAndPlan()
        let secondOutcome = try await secondGate.restoreInputQuarantineAndPlan()
        guard case let .broadcastApprovalRequired(firstCandidate) = firstOutcome,
              case let .broadcastApprovalRequired(secondCandidate) = secondOutcome else {
            Issue.record("Expected two authenticated recovery candidates")
            return
        }

        let firstBroadcast = MosaicBroadcastProbeActor(
            journalProbe: prepared.fixture.journalProbe
        )
        let firstCoordinator = try OpalBase.Account
            .MosaicTransactionBroadcastCoordinator(
                candidate: firstCandidate,
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                transactionClient: firstBroadcast.makeClient(
                    testingNetwork: prepared.fixture.network
                ),
                requestApproval: MosaicBroadcastApprovalTestSupport.approve
            )
        _ = try await firstCoordinator.broadcast()

        let staleBroadcast = MosaicBroadcastProbeActor(
            journalProbe: prepared.fixture.journalProbe
        )
        let staleCoordinator = try OpalBase.Account
            .MosaicTransactionBroadcastCoordinator(
                candidate: secondCandidate,
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                transactionClient: staleBroadcast.makeClient(
                    testingNetwork: prepared.fixture.network
                ),
                requestApproval: MosaicBroadcastApprovalTestSupport.approve
            )
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .journalPersistenceFailed
        ) {
            _ = try await staleCoordinator.broadcast()
        }
        #expect(await firstBroadcast.readBroadcasts().count == 1)
        #expect(await staleBroadcast.readBroadcasts().isEmpty)
    }

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

    @Test("Startup recovery re-quarantines exact journaled inputs")
    func quarantineRestoredInputsBeforeRecoveryAction() async throws {
        let prepared = try await makeCommittedAttempt()
        let records = await prepared.fixture.journalProbe.readRecords()
        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        #expect(
            await prepared.fixture.addressBook.listSpendableUTXOs()
                .contains(prepared.fixture.selectedInput)
        )

        let gate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let candidateOutcome = try await gate.restoreInputQuarantineAndPlan()
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
        let signingGate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            records: Array(records.prefix(3))
        )
        let signingOutcome = try await signingGate.restoreInputQuarantineAndPlan()
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
        let gate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            records: records
        )

        let missingInputOutcome = try await gate.restoreInputQuarantineAndPlan()
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
            let substitutedGate = try await makeRecoveryGate(
                addressBook: prepared.fixture.addressBook,
                records: substitutedRecords
            )
            _ = try await substitutedGate.restoreInputQuarantineAndPlan()
        }
    }

    @Test("Recovery rejects invalid journals, inputs, and broadcast candidates")
    func rejectInvalidRecoveryAuthority() async throws {
        let prepared = try await makeCommittedAttempt()
        let records = await prepared.fixture.journalProbe.readRecords()
        await #expect(
            throws: OpalBase.Account.MosaicAttemptJournalStore.Failure
                .invalidJournal(.invalidTransition)
        ) {
            _ = try await makeRecoveryGate(
                addressBook: prepared.fixture.addressBook,
                records: [records[0], records[4]]
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
            let duplicateInputGate = try await makeRecoveryGate(
                addressBook: prepared.fixture.addressBook,
                records: duplicateInputRecords
            )
            _ = try await duplicateInputGate.restoreInputQuarantineAndPlan()
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
            let futureVersionGate = try await makeRecoveryGate(
                addressBook: prepared.fixture.addressBook,
                records: futureVersionRecords
            )
            _ = try await futureVersionGate.restoreInputQuarantineAndPlan()
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
        await #expect(
            throws: OpalBase.Account.MosaicAttemptJournalStore.Failure
                .creationUncertain
        ) {
            _ = try await fixture.journalProbe.loadRecovery()
        }
        #expect(
            await fixture.addressBook.listSpendableUTXOs()
                .contains(fixture.selectedInput)
        )

        let lease = try await fixture.reserve()
        try await fixture.host.releaseMosaicReservation(lease.reference)
        let releasedGate = try await makeRecoveryGate(
            addressBook: fixture.addressBook,
            journalProbe: fixture.journalProbe
        )
        let releasedOutcome = try await releasedGate
            .restoreInputQuarantineAndPlan()
        guard case .released = releasedOutcome else {
            Issue.record("Expected terminal release recovery")
            return
        }
        #expect(
            await fixture.addressBook.listSpendableUTXOs()
                .contains(fixture.selectedInput)
        )
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

    @Test("Restarted recovery cannot repeat wallet or network effects")
    func recoverAuthenticatedSnapshotWithoutDuplicateEffects() async throws {
        let prepared = try await makeCommittedAttempt()
        let recordsBeforeRecovery = await prepared.fixture.journalProbe
            .readRecords()
        let envelopeBeforeRecovery = try #require(
            await prepared.fixture.journalProbe.readPersistedEnvelope()
        )
        #expect(await prepared.fixture.host.readSigningInvocationCount() == 1)

        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        let restartedJournalProbe = try await prepared.fixture.journalProbe
            .makeRestartedProbe()
        let gate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journalProbe: restartedJournalProbe
        )
        let outcome = try await gate.restoreInputQuarantineAndPlan()
        guard case .broadcastApprovalRequired = outcome else {
            Issue.record("Expected an authenticated committed recovery boundary")
            return
        }

        #expect(await prepared.fixture.host.readSigningInvocationCount() == 1)
        #expect(
            await restartedJournalProbe.readRecords()
                == recordsBeforeRecovery
        )
        #expect(
            await restartedJournalProbe.readPersistedEnvelope()
                == envelopeBeforeRecovery
        )
        await #expect(
            throws: OpalBase.Account.MosaicAttemptRecoveryGate.Failure
                .outcomeAlreadyIssued
        ) {
            _ = try await gate.restoreInputQuarantineAndPlan()
        }
        await #expect(
            throws: OpalBase.Account.MosaicAttemptJournalStore.Failure
                .alreadyExists
        ) {
            _ = try await restartedJournalProbe
                .makeFreshJournalForTesting()
        }
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

    private func makeRecoveryGate(
        addressBook: OpalBase.Address.Book,
        journalProbe: MosaicAttemptJournalProbeActor
    ) async throws -> OpalBase.Account.MosaicAttemptRecoveryGate {
        let recovery = try await journalProbe.loadRecovery()
        return .init(addressBook: addressBook, recovery: recovery)
    }

    private func makeRecoveryGate(
        addressBook: OpalBase.Address.Book,
        records: [OpalBase.Account.MosaicAttemptJournal.Record]
    ) async throws -> OpalBase.Account.MosaicAttemptRecoveryGate {
        let journalProbe = MosaicAttemptJournalProbeActor()
        let journal = try await journalProbe.makeFreshJournalForTesting()
        for record in records {
            try await journal.append(record)
        }
        return try await makeRecoveryGate(
            addressBook: addressBook,
            journalProbe: journalProbe
        )
    }
}
#endif
