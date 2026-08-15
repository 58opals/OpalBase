// AccountMosaicTransactionBroadcastCoordinatorValidator.swift

#if os(macOS)
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

@Suite("OpalBase.Account Mosaic transaction broadcast coordinator", .tags(.unit, .wallet))
struct AccountMosaicTransactionBroadcastCoordinatorValidator {
    typealias Planner = OpalBase.Account.MosaicAttemptRecoveryPlanner

    @Test("Persist broadcast intent before I/O and retry only exact bytes")
    func persistBroadcastIntentBeforeIO() async throws {
        let prepared = try await makeCommittedAttempt(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
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
        #expect(try isChainReconciliationPlan(completedRecords, hash: hash))
        let owner = try await makePrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let recoveryOutcome = try await owner.resume()
        guard case let .chainReconciliationRequired(recoveredState)
                = recoveryOutcome else {
            Issue.record("Expected chain reconciliation after accepted broadcast")
            return
        }
        #expect(recoveredState.transactionHash == hash)
    }

    @Test("Reconcile exact presence after accepted-result persistence fails")
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
        #expect(await broadcastProbe.readBroadcasts().count == 1)
        #expect(await approvalProbe.readRequests().count == 1)
        #expect(
            try isChainReconciliationPlan(
                await journalProbe.readRecords(),
                hash: hash
            )
        )
    }

    @Test("Ambiguous exact-byte mismatch after intent never dispatches")
    func holdPayloadMismatchAfterBroadcastIntent() async throws {
        let prepared = try await makeCommittedAttempt(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
        try await prepared.candidate.journal.append(
            .broadcastApproved(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        )
        try await prepared.candidate.journal.append(
            .broadcastIntent(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        )
        let interruptedRecords = await prepared.fixture.journalProbe
            .readRecords()
        let owner = try await makePrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let outcome = try await owner.resume()
        guard case let .resumeApprovedBroadcast(candidate) = outcome else {
            Issue.record("Expected approved intent recovery")
            return
        }

        var mismatchedBytes = Data(prepared.complete.transactionBytes)
        mismatchedBytes[mismatchedBytes.index(before: mismatchedBytes.endIndex)]
            ^= 0x01
        let broadcastProbe = MosaicBroadcastProbeActor(
            journalProbe: prepared.fixture.journalProbe,
            presenceTransactionDataOverride: mismatchedBytes
        )
        let coordinator = try OpalBase.Account
            .MosaicTransactionBroadcastCoordinator(
                candidate: candidate,
                securityProfile: MosaicBroadcastApprovalTestSupport
                    .securityProfile,
                transactionClient: broadcastProbe.makeClient(
                    testingNetwork: prepared.fixture.network
                ),
                requestApproval: MosaicBroadcastApprovalTestSupport.approve
            )

        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .reconciliationRequired
        ) {
            _ = try await coordinator.broadcast()
        }
        #expect(await broadcastProbe.readBroadcasts().isEmpty)
        #expect(
            await prepared.fixture.journalProbe.readRecords()
                == interruptedRecords
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
        #expect(await prepared.fixture.journalProbe.readRecords().count == 7)
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
        #expect(await prepared.fixture.journalProbe.readRecords().count == 7)
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
        #expect(await journalProbe.readRecords().count == 7)
        #expect(await broadcastProbe.readBroadcasts().isEmpty)

        _ = try await coordinator.broadcast()
        #expect(await approvalProbe.readRequests().count == 2)
        #expect(await broadcastProbe.readBroadcasts().count == 1)
        #expect(await journalProbe.readRecords().count == 10)
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
        #expect(await prepared.fixture.journalProbe.readRecords().count == 7)
        #expect(await broadcastProbe.readBroadcasts().isEmpty)
    }

    @Test("A legacy unapproved broadcast intent remains held without dispatch")
    func holdLegacyUnapprovedBroadcastIntent() async throws {
        let prepared = try await makeCommittedAttempt(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
        try await prepared.candidate.journal.append(
            .broadcastIntent(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        )
        let interruptedRecords = await prepared.fixture.journalProbe.readRecords()
        #expect(
            try Planner.plan(for: interruptedRecords)
                == .broadcastReconciliationHeld(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete
                )
        )

        let owner = try await makePrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let outcome = try await owner.resume()
        guard case .broadcastReconciliationHeld = outcome else {
            Issue.record("Expected a permanent no-dispatch recovery hold")
            return
        }
        await #expect(
            throws: OpalBase.Account.MosaicAttemptJournalStore.Failure
                .invalidJournal(.invalidTransition)
        ) {
            try await prepared.candidate.journal.append(
                .broadcastApproved(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete
                )
            )
        }
        #expect(await prepared.fixture.journalProbe.readRecords() == interruptedRecords)
    }

    @Test("Recovered durable approval persists intent before network I/O")
    func resumeApprovalCheckpointInFreshCoordinator() async throws {
        let prepared = try await makeCommittedAttempt(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
        try await prepared.candidate.journal.append(
            .broadcastApproved(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        )
        let owner = try await makePrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let outcome = try await owner.resume()
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
        #expect(await prepared.fixture.journalProbe.readRecords().count == 10)
        #expect(
            try isChainReconciliationPlan(
                await prepared.fixture.journalProbe.readRecords(),
                hash: hash
            )
        )
    }

    @Test("Recovered approved intent retries exact bytes without new approval")
    func resumeApprovedIntentInFreshCoordinator() async throws {
        let prepared = try await makeCommittedAttempt(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
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

        let recoveryOwner = try await makePrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let recoveryOutcome = try await recoveryOwner.resume()
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
        let prepared = try await makeCommittedAttempt(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )

        let firstOwner = try await makePrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let secondOwner = try await makePrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let firstOutcome = try await firstOwner.resume()
        let secondOutcome = try await secondOwner.resume()
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

    private func isChainReconciliationPlan(
        _ records: [OpalBase.Account.MosaicAttemptJournal.Record],
        hash: OpalBase.Transaction.Hash
    ) throws -> Bool {
        guard case let .reconcileChain(state) = try Planner.plan(for: records)
        else { return false }
        return state.transactionHash == hash
    }
}
#endif
