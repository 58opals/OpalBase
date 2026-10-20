#if os(macOS)
import Foundation
import Synchronization
import Testing
@_spi(MosaicPrivateAlpha) import OpalFusion
@_spi(MosaicPrivateAlpha) @testable import OpalBase
@testable import OpalBaseCore

@Suite("Mosaic immutable send authorization", .tags(.unit, .wallet))
struct AccountMosaicBroadcastAuthorizationValidator {
    typealias Runtime = OpalBase.Account.MosaicPrivateAlphaRuntime
    typealias Owner = OpalBase.Account.MosaicPrivateAlphaRecoveryOwner

    enum RetainedState: CaseIterable, Sendable { case fresh, approved, intent }
    enum Presence: CaseIterable, Sendable { case absent, present, unknown, mismatch }

    @Test("Every new send needs explicit authority, including retained approvals", arguments: RetainedState.allCases)
    func missingAuthorizationCannotSend(state: RetainedState) async throws {
        let fixture = try await makeFixture(state: state)
        let before = await fixture.journal.readRecords()
        await #expect(throws: Owner.Failure.broadcastNotApproved) {
            _ = try await fixture.owner.broadcastRecoveredTransaction(
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                using: fixture.probe.makeClient(),
                requestApproval: { _ in Issue.record("Missing authority must not request renewed approval"); return .approved }
            )
        }
        #expect(await fixture.probe.count == 0)
        #expect(await fixture.journal.readRecords() == before)
    }

    @Test("Fresh and resumed approvals remain exact and do not repeat consent", arguments: RetainedState.allCases)
    func validAuthorizationDispatchesExactBytes(state: RetainedState) async throws {
        let fixture = try await makeFixture(state: state)
        let approvals = Mutex(0)
        let result = try await fixture.owner.broadcastRecoveredTransaction(
            securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
            using: fixture.probe.makeClient(), authorizeSend: fixture.authorize,
            requestApproval: { _ in approvals.withLock { $0 += 1 }; return .approved }
        )
        #expect(result.transactionHash == fixture.authorization.request.transactionHash)
        #expect(await fixture.probe.count == 1)
        #expect(approvals.withLock { $0 } == (state == .fresh ? 1 : 0))
    }

    @Test("Approval expiring during durable journal persistence cannot dispatch", arguments: [RetainedState.fresh, .approved])
    func expiryDuringJournalPersistence(state: RetainedState) async throws {
        let fixture = try await makeFixture(state: state)
        let before = await fixture.journal.readRecords()
        let gate = MosaicOperationSuspensionProbeActor()
        await fixture.journal.suspendNextAppend(using: gate)
        let operation = Task {
            try await fixture.owner.broadcastRecoveredTransaction(
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                using: fixture.probe.makeClient(), authorizeSend: fixture.authorize,
                requestApproval: { _ in .approved }
            )
        }
        await gate.waitUntilSuspended()
        fixture.clock.set(fixture.expiresAt)
        await gate.resume()
        await #expect(throws: Owner.Failure.broadcastNotApproved) { _ = try await operation.value }
        #expect(await fixture.probe.count == 0)
        let retained = await fixture.journal.readRecords()
        #expect(Array(retained.prefix(before.count)) == before)
        #expect(retained.contains { if case .broadcastApproved = $0 { true } else { false } })
        #expect(retained.contains { if case .broadcastIntent = $0 { true } else { false } })
        #expect(retained.contains { if case .broadcastAccepted = $0 { true } else { false } } == false)
    }

    @Test("Expiry during fresh review cannot create broadcast authority")
    func expiryDuringApprovalCallback() async throws {
        let fixture = try await makeFixture(state: .fresh)
        let before = await fixture.journal.readRecords()
        let gate = MosaicOperationSuspensionProbeActor()
        let operation = Task {
            try await fixture.owner.broadcastRecoveredTransaction(
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                using: fixture.probe.makeClient(), authorizeSend: fixture.authorize,
                requestApproval: { _ in await gate.suspend(); return .approved }
            )
        }
        await gate.waitUntilSuspended()
        fixture.clock.set(fixture.expiresAt)
        await gate.resume()
        await #expect(throws: Owner.Failure.broadcastNotApproved) { _ = try await operation.value }
        #expect(await fixture.probe.count == 0)
        #expect(await fixture.journal.readRecords() == before)
    }

    @Test("Missing or expired authority preserves exact-present and unknown recovery", arguments: Presence.allCases, [false, true])
    func expiryDuringPresenceRead(presence: Presence, suppliesAuthorization: Bool) async throws {
        let gate = MosaicOperationSuspensionProbeActor()
        let fixture = try await makeFixture(state: .intent, presence: presence, presenceGate: gate)
        let before = await fixture.journal.readRecords()
        let operation = Task {
            try await fixture.owner.broadcastRecoveredTransaction(
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                using: fixture.probe.makeClient(), authorizeSend: suppliesAuthorization ? fixture.authorize : nil,
                requestApproval: { _ in Issue.record("Resumed approval must not renew consent"); return .approved }
            )
        }
        await gate.waitUntilSuspended()
        fixture.clock.set(fixture.expiresAt)
        await gate.resume()
        switch presence {
        case .present:
            let state = try await operation.value
            #expect(state.transactionHash == fixture.authorization.request.transactionHash)
            #expect(await fixture.journal.readRecords().count == before.count + 1)
        case .absent:
            await #expect(throws: Owner.Failure.broadcastNotApproved) { _ = try await operation.value }
            #expect(await fixture.journal.readRecords() == before)
        case .unknown, .mismatch:
            await #expect(throws: Owner.Failure.broadcastReconciliationRequired) { _ = try await operation.value }
            #expect(await fixture.journal.readRecords() == before)
        }
        #expect(await fixture.probe.count == 0)
    }

    @Test("Guarded custom transports recheck after their last actor wait")
    func expiryDuringTransportHandoff() async throws {
        let gate = MosaicOperationSuspensionProbeActor()
        let fixture = try await makeFixture(state: .fresh, sendGate: gate)
        let operation = Task {
            try await fixture.owner.broadcastRecoveredTransaction(
                securityProfile: MosaicBroadcastApprovalTestSupport.securityProfile,
                using: fixture.probe.makeClient(), authorizeSend: fixture.authorize,
                requestApproval: { _ in .approved }
            )
        }
        await gate.waitUntilSuspended()
        fixture.clock.set(fixture.expiresAt)
        await gate.resume()
        await #expect(throws: Owner.Failure.broadcastNotApproved) { _ = try await operation.value }
        #expect(await fixture.probe.count == 0)
        let retained = await fixture.journal.readRecords()
        #expect(retained.contains { if case .broadcastIntent = $0 { true } else { false } })
    }

    @Test("Authorization rejects time boundaries and transaction, reservation, protocol and endpoint substitution")
    func immutableAuthorizationRejectsSubstitutionAndInvalidTimes() async throws {
        let fixture = try await makeFixture(state: .fresh)
        let authorization = fixture.authorization
        let request = authorization.request
        #expect(fixture.authorize(fixture.request))
        for date in [fixture.confirmedAt.addingTimeInterval(-1), fixture.expiresAt, Date(timeIntervalSinceReferenceDate: .nan), Date(timeIntervalSinceReferenceDate: .infinity)] {
            #expect(!authorization.authorizes(request, binding: authorization.binding, attestation: authorization.attestation, at: date))
        }
        for (start, end) in [(fixture.confirmedAt, fixture.confirmedAt), (fixture.expiresAt, fixture.confirmedAt), (fixture.confirmedAt, request.reservationExpiresAt.addingTimeInterval(1)), (Date(timeIntervalSinceReferenceDate: .nan), fixture.expiresAt), (fixture.confirmedAt, Date(timeIntervalSinceReferenceDate: .infinity))] {
            #expect(Runtime.BroadcastAuthorization(request: request, binding: authorization.binding, attestation: authorization.attestation, operatorConfirmedAt: start, expiresAt: end) == nil)
        }
        let wrongBinding = try #require(Runtime.Binding(attemptIdentifier: Data(repeating: 0x99, count: 32), generationIdentifier: authorization.binding.generationIdentifier, materialIdentifier: authorization.binding.materialIdentifier))
        #expect(!authorization.authorizes(request, binding: wrongBinding, attestation: authorization.attestation, at: fixture.confirmedAt))
        let wrongEndpoints = Runtime.ChainAttestation(network: .mainnet, genesisHash: authorization.attestation.genesisHash, serverURLs: [URL(string: "wss://other.example:50004")!])
        #expect(!authorization.authorizes(request, binding: authorization.binding, attestation: wrongEndpoints, at: fixture.confirmedAt))
        let internalRequest = fixture.request
        let otherReference = OpalFusion.Host.MosaicReservationReference(identifier: UUID(), generation: internalRequest.reservationReference.generation)
        let otherGeneration = OpalFusion.Host.MosaicReservationReference(identifier: internalRequest.reservationReference.identifier, generation: internalRequest.reservationReference.generation + 1)
        let original = try OpalBase.Transaction.decode(from: request.transactionBytes).transaction
        let transaction = OpalBase.Transaction(version: original.version, inputs: original.inputs, outputs: original.outputs, lockTime: original.lockTime + 1)
        let otherTransaction = try OpalFusion.Host.MosaicCompleteTransaction(transactionBytes: [UInt8](transaction.encode()))
        for changed in [
            copy(internalRequest, reference: otherReference),
            copy(internalRequest, reference: otherGeneration),
            copy(internalRequest, transaction: otherTransaction),
            copy(internalRequest, network: .chipnet)
        ] {
            #expect(!fixture.authorize(changed))
        }
    }

    private func copy(
        _ value: OpalBase.Account.MosaicTransactionBroadcastCoordinator.ApprovalRequest,
        reference: OpalFusion.Host.MosaicReservationReference? = nil,
        transaction: OpalFusion.Host.MosaicCompleteTransaction? = nil,
        network: OpalBase.Network.Environment? = nil
    ) -> OpalBase.Account.MosaicTransactionBroadcastCoordinator.ApprovalRequest {
        .init(reservationRequest: value.reservationRequest, reservationReference: reference ?? value.reservationReference, completeTransaction: transaction ?? value.completeTransaction, profile: value.profile, network: network ?? value.network, totalInputSatoshis: value.totalInputSatoshis, totalOutputSatoshis: value.totalOutputSatoshis, feeSatoshis: value.feeSatoshis)
    }

    private struct Fixture: Sendable {
        let owner: Owner
        let journal: MosaicAttemptJournalProbeActor
        let probe: DispatchProbe
        let request: OpalBase.Account.MosaicTransactionBroadcastCoordinator.ApprovalRequest
        let authorization: Runtime.BroadcastAuthorization
        let clock: Clock
        let confirmedAt: Date
        let expiresAt: Date
        var authorize: @Sendable (OpalBase.Account.MosaicTransactionBroadcastCoordinator.ApprovalRequest) -> Bool {
            { current in
                guard let request = Runtime.BroadcastApprovalRequest(current) else { return false }
                return authorization.authorizes(request, binding: authorization.binding, attestation: authorization.attestation, at: clock.now)
            }
        }
    }

    private func makeFixture(state: RetainedState, presence: Presence = .absent, presenceGate: MosaicOperationSuspensionProbeActor? = nil, sendGate: MosaicOperationSuspensionProbeActor? = nil) async throws -> Fixture {
        let prepared = try await makeCommittedAttempt(profile: .opalMainnetAlpha, network: .mainnet)
        if state != .fresh {
            try await prepared.candidate.journal.append(.broadcastApproved(reference: prepared.lease.reference, transaction: prepared.complete))
        }
        if state == .intent {
            try await prepared.candidate.journal.append(.broadcastIntent(reference: prepared.lease.reference, transaction: prepared.complete))
        }
        let owner = try await makePrivateAlphaRecoveryOwner(addressBook: prepared.fixture.addressBook, journalProbe: prepared.fixture.journalProbe)
        _ = try await owner.resume()
        let exact = try OpalBase.Account.MosaicExactTransaction(prepared.complete)
        let probe = DispatchProbe(transaction: exact, presence: presence, presenceGate: presenceGate, sendGate: sendGate)
        let request = try await owner.loadBroadcastApprovalRequest(using: probe.makeClient())
        let publicRequest = try #require(Runtime.BroadcastApprovalRequest(request))
        let binding = await owner.binding
        let publicBinding = try #require(Runtime.Binding(attemptIdentifier: binding.attemptIdentifier, generationIdentifier: binding.generationIdentifier, materialIdentifier: binding.materialIdentifier))
        let confirmedAt = publicRequest.reservationExpiresAt.addingTimeInterval(-120)
        let expiresAt = confirmedAt.addingTimeInterval(60)
        let authorization = try #require(Runtime.BroadcastAuthorization(request: publicRequest, binding: publicBinding, attestation: .init(network: .mainnet, genesisHash: publicRequest.expectedNetworkGenesisHash, serverURLs: [URL(string: "wss://fulcrum.example:50004")!]), operatorConfirmedAt: confirmedAt, expiresAt: expiresAt))
        return .init(owner: owner, journal: prepared.fixture.journalProbe, probe: probe, request: request, authorization: authorization, clock: Clock(confirmedAt), confirmedAt: confirmedAt, expiresAt: expiresAt)
    }

    private final class Clock: Sendable {
        private let value: Mutex<Date>
        init(_ value: Date) { self.value = Mutex(value) }
        var now: Date { value.withLock { $0 } }
        func set(_ value: Date) { self.value.withLock { $0 = value } }
    }

    private actor DispatchProbe {
        let transaction: OpalBase.Account.MosaicExactTransaction
        let presence: Presence
        let presenceGate: MosaicOperationSuspensionProbeActor?
        let sendGate: MosaicOperationSuspensionProbeActor?
        private(set) var count = 0

        init(transaction: OpalBase.Account.MosaicExactTransaction, presence: Presence, presenceGate: MosaicOperationSuspensionProbeActor?, sendGate: MosaicOperationSuspensionProbeActor?) {
            self.transaction = transaction; self.presence = presence
            self.presenceGate = presenceGate; self.sendGate = sendGate
        }

        nonisolated func makeClient() -> OpalBase.Account.MosaicNetworkAttestedTransactionClient {
            .init(testingNetwork: .mainnet, transactionClient: .init(
                broadcastTransaction: { _ in Issue.record("Guarded sends cannot use the legacy operation"); throw MosaicBroadcastProbeFailure.scripted },
                authorizedBroadcastTransaction: { raw, authorization in try await self.send(raw, authorization: authorization) },
                fetchConfirmations: { _ in nil },
                fetchConfirmationStatus: { hash in .init(transactionHash: hash, transactionHeight: nil, tipHeight: 0, confirmations: nil) }
            ), fetchFreshDetailedTransaction: { hash in try await self.readPresence(hash) })
        }

        private func send(_ raw: String, authorization: OpalBase.Network.TransactionSendAuthorization) async throws -> String {
            if let sendGate { await sendGate.suspend() }
            try authorization.requireAuthorized()
            count += 1
            #expect(raw == transaction.bytes.hexadecimalString)
            return transaction.hash.reverseOrder.hexadecimalString
        }

        private func readPresence(_ hash: OpalBase.Transaction.Hash) async throws -> OpalBase.Transaction.Detail {
            if let presenceGate { await presenceGate.suspend() }
            switch presence {
            case .absent: throw OpalBase.Network.Error(reason: .server(code: -5))
            case .unknown: throw OpalBase.Network.Error(reason: .network)
            case .present, .mismatch:
                return .init(transaction: transaction.transaction, blockHash: nil, blockTime: nil, confirmations: 0, hash: hash, rawTransactionData: presence == .mismatch ? Data([0]) : transaction.bytes, size: UInt32(transaction.bytes.count), time: nil)
            }
        }
    }
}
#endif
