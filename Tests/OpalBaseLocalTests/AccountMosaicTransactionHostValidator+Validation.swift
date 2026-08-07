// AccountMosaicTransactionHostValidator+Validation.swift

#if os(macOS)
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

extension AccountMosaicTransactionHostValidator {
    @Test("Malformed proposals are rejected before policy validation or signing")
    func rejectMalformedProposalBeforePolicyOrSigning() async throws {
        let probe = MosaicPolicyProbeActor()
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: await probe.transactionPolicy
        )
        let lease = try await fixture.reserve()
        let expectedOutput = try #require(lease.participantReservation.outputs.first)
        let mismatchedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: fixture.selectedInput.previousTransactionHash,
                    previousTransactionOutputIndex: fixture.selectedInput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                )
            ],
            outputs: [
                .init(
                    value: expectedOutput.amountSatoshis - 1,
                    lockingScript: Data(expectedOutput.lockingScriptBytes)
                )
            ],
            lockTime: 0
        )
        let request = try fixture.makeSigningRequest(
            lease: lease,
            transaction: mismatchedTransaction
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.invalidTransactionProposal) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        #expect(await probe.readInvocationCount() == 0)
        #expect(await fixture.host.readSigningInvocationCount() == 0)
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test("Token-bearing outputs are rejected before policy validation or signing")
    func rejectTokenOutputBeforePolicyOrSigning() async throws {
        let probe = MosaicPolicyProbeActor()
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: await probe.transactionPolicy
        )
        let lease = try await fixture.reserve()
        let expectedOutput = try #require(lease.participantReservation.outputs.first)
        let tokenTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: fixture.selectedInput.previousTransactionHash,
                    previousTransactionOutputIndex: fixture.selectedInput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                )
            ],
            outputs: [
                .init(
                    value: expectedOutput.amountSatoshis,
                    lockingScript: Data(expectedOutput.lockingScriptBytes),
                    tokenData: try CashFusionTestSupport.makeTokenData()
                )
            ],
            lockTime: 0
        )
        let request = try fixture.makeSigningRequest(
            lease: lease,
            transaction: tokenTransaction
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.invalidTransactionProposal) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        #expect(await probe.readInvocationCount() == 0)
        #expect(await fixture.host.readSigningInvocationCount() == 0)
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test("A rejected transaction policy stops BCH signing")
    func rejectTransactionPolicyBeforeSigning() async throws {
        let probe = MosaicPolicyProbeActor(rejectsProposal: true)
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: await probe.transactionPolicy
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)

        await #expect(throws: OpalBase.Account.MosaicHostFailure.transactionPolicyRejected) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        #expect(await probe.readInvocationCount() == 1)
        #expect(await fixture.host.readSigningInvocationCount() == 0)
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test("Transcript profile substitutions fail before policy validation or signing")
    func rejectTranscriptProfileSubstitution() async throws {
        let profileProbe = MosaicPolicyProbeActor()
        let draftFixture = try await MosaicHostFixture.make(
            transactionPolicy: await profileProbe.transactionPolicy
        )
        let draftLease = try await draftFixture.reserve()
        let substitutedProfile = try draftFixture.makeSigningRequest(
            lease: draftLease,
            transcriptProfile: .opalV0
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.invalidTransactionProposal) {
            _ = try await draftFixture.host.finalizeMosaicTransaction(
                for: substitutedProfile
            )
        }
        #expect(await profileProbe.readInvocationCount() == 0)
        #expect(await draftFixture.host.readSigningInvocationCount() == 0)
        try await draftFixture.host.releaseMosaicReservation(draftLease.reference)

        let networkProbe = MosaicPolicyProbeActor()
        let testnetFixture = try await MosaicHostFixture.make(
            transactionPolicy: await networkProbe.transactionPolicy,
            network: .testnet,
            profile: .opalV0,
            minimumExcessFeeSatoshis: 0,
            maximumExcessFeeSatoshis: 0
        )
        let testnetLease = try await testnetFixture.reserve()
        let wrongNetwork = try testnetFixture.makeSigningRequest(lease: testnetLease)

        await #expect(throws: OpalBase.Account.MosaicHostFailure.invalidTransactionProposal) {
            _ = try await testnetFixture.host.finalizeMosaicTransaction(for: wrongNetwork)
        }
        #expect(await networkProbe.readInvocationCount() == 0)
        #expect(await testnetFixture.host.readSigningInvocationCount() == 0)
        try await testnetFixture.host.releaseMosaicReservation(testnetLease.reference)
    }
}
#endif
