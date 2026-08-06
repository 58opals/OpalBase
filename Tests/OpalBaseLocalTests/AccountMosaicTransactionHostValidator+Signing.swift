// AccountMosaicTransactionHostValidator+Signing.swift

#if os(macOS)
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

extension AccountMosaicTransactionHostValidator {
    @Test("Only local inputs receive Schnorr ALL|FORKID signatures")
    func signOnlyLocalInputsAndCommitIdempotently() async throws {
        let remote = try await makeRemoteInput()
        let probe = MosaicPolicyProbeActor(expectedFeeSatoshis: 90_000)
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: await probe.transactionPolicy
        )
        let lease = try await fixture.reserve()
        let localInput = try #require(lease.participantReservation.inputs.first)
        let localOutput = try #require(lease.participantReservation.outputs.first)
        let unsignedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: remote.unspentOutput.previousTransactionHash,
                    previousTransactionOutputIndex: remote.unspentOutput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                ),
                .init(
                    previousTransactionHash: fixture.selectedInput.previousTransactionHash,
                    previousTransactionOutputIndex: fixture.selectedInput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                )
            ],
            outputs: [
                .init(
                    value: localOutput.amountSatoshis,
                    lockingScript: Data(localOutput.lockingScriptBytes)
                )
            ],
            lockTime: 0
        )
        let request = try makeSigningRequest(
            fixture: fixture,
            lease: lease,
            transaction: unsignedTransaction,
            spentInputs: [remote.participantInput, localInput],
            localInputIndices: [1],
            transcriptByte: 0x44
        )

        let finalized = try await fixture.host.finalizeMosaicTransaction(for: request)
        let duplicate = try await fixture.host.finalizeMosaicTransaction(for: request)
        let decoded = try OpalBase.Transaction.decode(
            from: Data(finalized.signedFusionTransactionBytes)
        ).transaction

        #expect(duplicate == finalized)
        #expect(decoded.inputs[0].unlockingScript.isEmpty)
        #expect(decoded.inputs[1].unlockingScript.count == 100)
        #expect(decoded.inputs[1].unlockingScript[65] == 0x41)
        #expect(await probe.readInvocationCount() == 1)
        #expect(await fixture.host.readSigningInvocationCount() == 1)

        let conflictingRequest = try makeSigningRequest(
            fixture: fixture,
            lease: lease,
            transaction: unsignedTransaction,
            spentInputs: [remote.participantInput, localInput],
            localInputIndices: [1],
            transcriptByte: 0x45
        )
        await #expect(throws: OpalBase.Account.MosaicHostFailure.conflictingFinalization) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: conflictingRequest)
        }
        await #expect(throws: OpalBase.Account.MosaicHostFailure.finalizationRequired) {
            try await fixture.host.commitMosaicReservation(
                lease.reference,
                finalizedTransaction: .init(signedFusionTransactionBytes: [0x00])
            )
        }

        try await fixture.host.commitMosaicReservation(
            lease.reference,
            finalizedTransaction: finalized
        )
        try await fixture.host.commitMosaicReservation(
            lease.reference,
            finalizedTransaction: finalized
        )
        #expect(!(await fixture.addressBook.listSpendableUTXOs()).contains(fixture.selectedInput))
    }
}

private extension AccountMosaicTransactionHostValidator {
    func makeRemoteInput() async throws -> (
        unspentOutput: OpalBase.Transaction.Output.Unspent,
        participantInput: OpalFusion.Host.ParticipantInput
    ) {
        let account = try await AccountTestFixtures.makeAccount(unhardenedIndex: 1)
        let unspentOutput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 80_000,
            usage: .change,
            hashByte: 0xb2
        )
        let addressBook = await account.addressBook
        let script = try OpalBase.Script.decode(lockingScript: unspentOutput.lockingScript)
        let address = try OpalBase.Address(script: script)
        let entry = try #require(await addressBook.findEntry(for: address))
        let signingKey = try await addressBook.generateSigningKey(
            at: entry.derivationPath.index,
            for: entry.derivationPath.usage
        )
        return (
            unspentOutput,
            .init(
                outpointTransactionHashBytes: [UInt8](unspentOutput.previousTransactionHash.reverseOrder),
                outpointIndex: unspentOutput.previousTransactionOutputIndex,
                amountSatoshis: unspentOutput.value,
                lockingScriptBytes: [UInt8](unspentOutput.lockingScript),
                publicKey: [UInt8](signingKey.publicKey.compressedData)
            )
        )
    }

    func makeSigningRequest(
        fixture: MosaicHostFixture,
        lease: OpalFusion.Host.MosaicReservationLease,
        transaction: OpalBase.Transaction,
        spentInputs: [OpalFusion.Host.ParticipantInput],
        localInputIndices: [Int],
        transcriptByte: UInt8
    ) throws -> OpalFusion.Host.MosaicTransactionSigningRequest {
        try .init(
            reservationReference: lease.reference,
            roundIdentifier: fixture.reservationRequest.roundIdentifier,
            transcriptRoot: Array(repeating: transcriptByte, count: 32),
            unsignedTransactionBytes: [UInt8](try transaction.encode()),
            spentInputs: spentInputs,
            localInputIndices: localInputIndices,
            expectedLocalOutputs: lease.participantReservation.outputs,
            feeRateSatoshisPerByte: fixture.reservationRequest.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: fixture.reservationRequest.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: fixture.reservationRequest.maximumExcessFeeSatoshis,
            transactionProfileIdentifier: fixture.reservationRequest.transactionProfileIdentifier
        )
    }
}
#endif
