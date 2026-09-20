// AccountMosaicTransactionHostValidator+SigningApproval.swift

#if os(macOS)
import Foundation
import OpalFusion
import Synchronization
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase

extension AccountMosaicTransactionHostValidator {
    @Test("Application approval receives the validated proposal before any signature", .timeLimit(.minutes(1)))
    func approveExactUnsignedProposalBeforeSigning() async throws {
        typealias Request = OpalBase.Account.MosaicPrivateAlphaRuntime.SigningApprovalRequest
        let captured = Mutex<[Request]>([])
        let suspension = MosaicOperationSuspensionProbeActor()
        let policyProbe = MosaicPolicyProbeActor()
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: await policyProbe.transactionPolicy,
            signingApproval: .init { request in
                #expect(await policyProbe.readInvocationCount() == 1)
                captured.withLock { $0.append(request) }
                await suspension.suspend()
            }
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let before = await fixture.journalProbe.readRecords()
        let task = Task { try await fixture.host.finalizeMosaicTransaction(for: request) }
        await suspension.waitUntilSuspended()
        #expect(await fixture.host.readSigningInvocationCount() == 0)
        #expect(await fixture.journalProbe.readRecords() == before)
        let review = try #require(captured.withLock { $0.first })
        #expect(review.unsignedTransactionBytes == Data(request.unsignedTransactionBytes))
        #expect(review.roundIdentifier == Data(request.roundIdentifier))
        #expect(review.transcriptRoot == Data(request.transcriptRoot))
        #expect(review.walletReservationIdentifier == lease.reference.identifier)
        #expect(review.walletGeneration == lease.reference.generation)
        #expect(review.reservationExpiresAt == lease.expiresAt)
        #expect(review.expectedNetworkGenesisHash == Data(fixture.reservationRequest.networkGenesisHash))
        #expect(review.localInputIndices == request.localInputIndices)
        #expect(review.spentInputs.count == 1)
        #expect(review.spentInputs.first?.transactionHash == fixture.selectedInput.previousTransactionHash)
        #expect(review.spentInputs.first?.outputIndex == request.spentInputs[0].outpointIndex)
        #expect(review.spentInputs.first?.valueSatoshis == fixture.selectedInput.value)
        #expect(review.expectedLocalOutputs.first?.valueSatoshis == lease.participantReservation.outputs[0].amountSatoshis)
        let proposal = try OpalBase.Transaction.decode(from: review.unsignedTransactionBytes).transaction
        #expect(review.outputs.map(\.serializedBytes) == (try proposal.outputs.map { try $0.encode() }))
        #expect(review.outputs.map(\.lockingScript) == proposal.outputs.map(\.lockingScript))
        #expect(review.expectedLocalOutputs.allSatisfy { review.outputs.contains($0) })
        #expect(review.feeSatoshis == 10_000)
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        await suspension.resume()
        let signed = try await task.value
        #expect(await fixture.host.readSigningInvocationCount() == 1)
        #expect(try await fixture.host.finalizeMosaicTransaction(for: request) == signed)
        #expect(captured.withLock { $0.count } == 1)
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            try await fixture.host.releaseMosaicReservation(lease.reference)
        }
    }

    @Test("Rejected validation or application approval cannot reach signing intent", arguments: [false, true])
    func rejectBeforeSigningIntent(policyRejects: Bool) async throws {
        let count = Mutex(0)
        let probe = MosaicPolicyProbeActor(rejectsProposal: policyRejects)
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: await probe.transactionPolicy,
            signingApproval: .init { _ in
                count.withLock { $0 += 1 }
                throw MosaicPolicyFixtureFailure.rejected
            }
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let before = await fixture.journalProbe.readRecords()
        await #expect(throws: OpalBase.Account.MosaicHostFailure.transactionPolicyRejected) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        #expect(count.withLock { $0 } == (policyRejects ? 0 : 1))
        #expect(await fixture.host.readSigningInvocationCount() == 0)
        #expect(await fixture.journalProbe.readRecords() == before)
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test("Cancellation and expiry after approval never cross into signing", .timeLimit(.minutes(1)), arguments: [false, true])
    func stopAfterSuspendedSigningApproval(cancel: Bool) async throws {
        let suspension = MosaicOperationSuspensionProbeActor()
        let clock = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: await MosaicPolicyProbeActor().transactionPolicy,
            signingApproval: .init { _ in await suspension.suspend() },
            currentDate: { clock.withLock { $0 } }
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let task = Task { try await fixture.host.finalizeMosaicTransaction(for: request) }
        await suspension.waitUntilSuspended()
        if cancel { task.cancel() }
        else { clock.withLock { $0 = lease.expiresAt } }
        await suspension.resume()
        if cancel {
            await #expect(throws: CancellationError.self) { _ = try await task.value }
            try await fixture.host.releaseMosaicReservation(lease.reference)
        } else {
            await #expect(throws: OpalBase.Account.MosaicHostFailure.reservationExpired) { _ = try await task.value }
        }
        #expect(await fixture.host.readSigningInvocationCount() == 0)
        for record in await fixture.journalProbe.readRecords() {
            if case .signingIntent = record { Issue.record("Approval crossed into durable signing intent") }
            if case .locallySigned = record { Issue.record("Approval crossed into local signing") }
        }
    }
}
#endif
