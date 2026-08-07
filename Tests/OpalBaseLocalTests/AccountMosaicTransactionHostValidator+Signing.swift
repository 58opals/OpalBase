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
        let locallySigned = try OpalBase.Transaction.decode(
            from: Data(finalized.signedFusionTransactionBytes)
        ).transaction

        #expect(duplicate == finalized)
        #expect(locallySigned.inputs[0].unlockingScript.isEmpty)
        #expect(locallySigned.inputs[1].unlockingScript.count == 100)
        #expect(locallySigned.inputs[1].unlockingScript[65] == 0x41)
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
        await #expect(throws: OpalBase.Account.MosaicHostFailure.completeTransactionRequired) {
            try await fixture.host.commitMosaicReservation(
                lease.reference,
                finalizedTransaction: finalized
            )
        }
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            try await fixture.host.releaseMosaicReservation(lease.reference)
        }

        let incomplete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: finalized.signedFusionTransactionBytes
        )
        await #expect(throws: OpalBase.Account.MosaicHostFailure.invalidCompleteTransaction) {
            try await fixture.host.commitMosaicReservation(
                lease.reference,
                completeTransaction: incomplete
            )
        }

        let completeTransaction = try locallySigned.signInputInPlace(
            at: 0,
            spending: remote.unspentOutput,
            signingKey: remote.signingKey,
            signatureFormat: .schnorr,
            unlocker: .p2pkh_CheckSig(
                hashType: .makeAll(anyoneCanPay: false)
            ),
            using: unsignedTransaction
        )
        let complete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: [UInt8](try completeTransaction.encode())
        )

        try await fixture.host.commitMosaicReservation(
            lease.reference,
            completeTransaction: complete
        )
        try await fixture.host.commitMosaicReservation(
            lease.reference,
            completeTransaction: complete
        )
        #expect(!(await fixture.addressBook.listSpendableUTXOs()).contains(fixture.selectedInput))

        var conflictingBytes = complete.transactionBytes
        conflictingBytes[conflictingBytes.index(before: conflictingBytes.endIndex)] ^= 0x01
        let conflictingComplete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: conflictingBytes
        )
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure.conflictingCompleteTransaction
        ) {
            try await fixture.host.commitMosaicReservation(
                lease.reference,
                completeTransaction: conflictingComplete
            )
        }
    }

    @Test("Reject malformed body and signature changes before complete commit")
    func rejectMalformedCompleteTransactions() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(transactionPolicy: policy)
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let finalized = try await fixture.host.finalizeMosaicTransaction(for: request)
        let signed = try OpalBase.Transaction.decode(
            from: Data(finalized.signedFusionTransactionBytes)
        ).transaction

        var trailingBytes = finalized.signedFusionTransactionBytes
        trailingBytes.append(0)
        let trailing = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: trailingBytes
        )
        await #expect(throws: OpalBase.Account.MosaicHostFailure.invalidCompleteTransaction) {
            try await fixture.host.commitMosaicReservation(
                lease.reference,
                completeTransaction: trailing
            )
        }

        var tamperedScript = signed.inputs[0].unlockingScript
        tamperedScript[1] ^= 0x01
        let tamperedSignature = OpalBase.Transaction(
            version: signed.version,
            inputs: [
                .init(
                    previousTransactionHash: signed.inputs[0].previousTransactionHash,
                    previousTransactionOutputIndex:
                        signed.inputs[0].previousTransactionOutputIndex,
                    unlockingScript: tamperedScript,
                    sequence: signed.inputs[0].sequence
                )
            ],
            outputs: signed.outputs,
            lockTime: signed.lockTime
        )
        let invalidSignature = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: [UInt8](try tamperedSignature.encode())
        )
        await #expect(throws: OpalBase.Account.MosaicHostFailure.invalidCompleteTransaction) {
            try await fixture.host.commitMosaicReservation(
                lease.reference,
                completeTransaction: invalidSignature
            )
        }

        let changedBody = OpalBase.Transaction(
            version: signed.version,
            inputs: signed.inputs,
            outputs: signed.outputs.map {
                .init(
                    value: $0.value - 1,
                    lockingScript: $0.lockingScript,
                    tokenData: $0.tokenData
                )
            },
            lockTime: signed.lockTime
        )
        let invalidBody = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: [UInt8](try changedBody.encode())
        )
        await #expect(throws: OpalBase.Account.MosaicHostFailure.invalidCompleteTransaction) {
            try await fixture.host.commitMosaicReservation(
                lease.reference,
                completeTransaction: invalidBody
            )
        }

        let complete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: finalized.signedFusionTransactionBytes
        )
        try await fixture.host.commitMosaicReservation(
            lease.reference,
            completeTransaction: complete
        )
    }
}

private extension AccountMosaicTransactionHostValidator {
    func makeRemoteInput() async throws -> (
        unspentOutput: OpalBase.Transaction.Output.Unspent,
        participantInput: OpalFusion.Host.ParticipantInput,
        signingKey: OpalBase.Key.SigningKey
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
            ),
            signingKey
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
        let unsignedTransactionBytes = [UInt8](try transaction.encode())
        return try .init(
            reservationReference: lease.reference,
            roundIdentifier: fixture.reservationRequest.roundIdentifier,
            transcriptBinding: try MosaicHostFixture.makeTranscriptBinding(
                profile: fixture.profile,
                unsignedTransactionBytes: unsignedTransactionBytes,
                discriminator: transcriptByte
            ),
            unsignedTransactionBytes: unsignedTransactionBytes,
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
