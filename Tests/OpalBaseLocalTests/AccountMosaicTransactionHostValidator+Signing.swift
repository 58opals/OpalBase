// AccountMosaicTransactionHostValidator+Signing.swift

#if os(macOS)
import Foundation
import OpalCrypto
import OpalFusion
import Testing
@testable import OpalBase

extension AccountMosaicTransactionHostValidator {
    @Test("Mainnet alpha reserves, signs, and commits exact synthetic bytes")
    func completeSyntheticMainnetAlphaHostLifecycle() async throws {
        let profile = OpalFusion.Mosaic.Profile.opalMainnetAlpha
        let network = OpalBase.Network.Environment.mainnet
        let localRequiredExcessFeeSatoshis: UInt64 = 2
        let remoteRequiredExcessFeeSatoshis: [UInt64] = [2, 2, 2, 1, 1]
        let account = try await AccountTestFixtures.makeAccount()
        let addressBook = await account.addressBook
        let inputEntry = try await addressBook.selectNextEntry(for: .change)
        let localPreviousOutput = OpalBase.Transaction.Output(
            value: 100_000,
            lockingScript: inputEntry.address.lockingScript.data
        )
        let localPreviousTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: .init(
                        naturalOrder: Data(repeating: 0x91, count: 32)
                    ),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data([0x51])
                )
            ],
            outputs: [localPreviousOutput],
            lockTime: 0
        )
        let rawLocalPreviousTransaction = try localPreviousTransaction.encode()
        let localPreviousTransactionHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCrypto.Hashing.hash256(rawLocalPreviousTransaction)
        )
        let selectedInput = OpalBase.Transaction.Output.Unspent(
            output: localPreviousOutput,
            previousTransactionHash: localPreviousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        await addressBook.addUTXOs([selectedInput])

        var remoteContributions: [SyntheticMainnetAlphaContribution] = []
        var rawPreviousTransactions: [OpalBase.Transaction.Hash: Data] = [
            localPreviousTransactionHash: rawLocalPreviousTransaction
        ]
        for (offset, share) in remoteRequiredExcessFeeSatoshis.enumerated() {
            let seed = UInt8(0x31 + offset)
            let amountSatoshis = UInt64(110_000 + (offset * 10_000))
            let material = try MosaicProfileTransactionPolicyFixture.makeInputMaterial(
                seed: seed,
                amountSatoshis: amountSatoshis
            )
            let signingKey = try OpalBase.Key.SigningKey(
                rawRepresentation: Data(repeating: seed, count: 32)
            )
            let unspentOutput = OpalBase.Transaction.Output.Unspent(
                value: material.participantInput.amountSatoshis,
                lockingScript: Data(material.participantInput.lockingScriptBytes),
                previousTransactionHash: material.transactionHash,
                previousTransactionOutputIndex: material.participantInput.outpointIndex
            )
            let contributionSatoshis = 141 + 34 + share
            let outputLockingScript = try MosaicProfileTransactionPolicyFixture
                .makeP2PKHLockingScript(seed: seed &+ 0x20)
            remoteContributions.append(
                .init(
                    participantInput: material.participantInput,
                    transactionInput: material.transactionInput,
                    unspentOutput: unspentOutput,
                    output: .init(
                        value: amountSatoshis - contributionSatoshis,
                        lockingScript: outputLockingScript
                    ),
                    signingKey: signingKey,
                    isLocal: false
                )
            )
            rawPreviousTransactions[material.transactionHash] = material.rawPreviousTransaction
        }

        let previousTransactions = rawPreviousTransactions
        let transactionReader = OpalBase.Network.TransactionReader { hash in
            guard let transaction = previousTransactions[hash] else {
                throw MosaicProfileTransactionPolicyFixture.FixtureFailure
                    .missingPreviousTransaction
            }
            return transaction
        }
        let journalProbe = MosaicAttemptJournalProbeActor()
        let reservationIdentifier = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")
        )
        let host = try OpalBase.Account.MosaicTransactionHostActor(
            addressBook: addressBook,
            profile: profile,
            network: network,
            generation: 2,
            selectedInputs: [selectedInput],
            outputAmountsSatoshis: [
                localPreviousOutput.value - 141 - 34 - localRequiredExcessFeeSatoshis
            ],
            transactionPolicy: try .init(
                profile: profile,
                network: network,
                transactionReader: transactionReader
            ),
            attemptJournal: journalProbe.makeJournal(),
            currentDate: { Date(timeIntervalSince1970: 1_800_000_000) },
            makeReservationIdentifier: { reservationIdentifier }
        )
        let reservationRequest = try OpalFusion.Host.MosaicReservationRequest(
            attemptIdentifier: [0xA2],
            networkGenesisHash: network.mosaicGenesisHash,
            roundIdentifier: Array(repeating: 0xA3, count: 32),
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            componentCount: profile.rosterPolicy.componentCountPerContributor,
            feeRateSatoshisPerByte: 1,
            minimumExcessFeeSatoshis: 1,
            maximumExcessFeeSatoshis: 2,
            requiredExcessFeeSatoshis: localRequiredExcessFeeSatoshis,
            transactionProfileIdentifier: profile.transactionProfileIdentifier
        )
        let lease = try await host.reserveMosaicContribution(
            for: reservationRequest
        )
        let localOutput = try #require(
            lease.participantReservation.outputs.first
        )
        let localParticipantInput = try #require(
            lease.participantReservation.inputs.first
        )
        let localContribution = SyntheticMainnetAlphaContribution(
            participantInput: localParticipantInput,
            transactionInput: .init(
                previousTransactionHash: localPreviousTransactionHash,
                previousTransactionOutputIndex: 0,
                unlockingScript: Data()
            ),
            unspentOutput: selectedInput,
            output: .init(
                value: localOutput.amountSatoshis,
                lockingScript: Data(localOutput.lockingScriptBytes)
            ),
            signingKey: nil,
            isLocal: true
        )
        let orderedContributions = (remoteContributions + [localContribution]).sorted {
            let leftHash = $0.transactionInput.previousTransactionHash.reverseOrder
            let rightHash = $1.transactionInput.previousTransactionHash.reverseOrder
            if leftHash != rightHash {
                return leftHash.lexicographicallyPrecedes(rightHash)
            }
            return $0.transactionInput.previousTransactionOutputIndex
                < $1.transactionInput.previousTransactionOutputIndex
        }
        let localInputIndex = try #require(
            orderedContributions.firstIndex { $0.isLocal }
        )
        let orderedOutputs = orderedContributions.map(\.output).sorted {
            if $0.value != $1.value {
                return $0.value < $1.value
            }
            return $0.lockingScript.lexicographicallyPrecedes($1.lockingScript)
        }
        let unsignedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: orderedContributions.map(\.transactionInput),
            outputs: orderedOutputs,
            lockTime: 0
        )
        let inputValue = orderedContributions.reduce(UInt64(0)) {
            $0 + $1.participantInput.amountSatoshis
        }
        let outputValue = orderedOutputs.reduce(UInt64(0)) { $0 + $1.value }
        let contributionDeltas = orderedContributions.map {
            $0.participantInput.amountSatoshis - $0.output.value
        }.sorted()
        #expect(contributionDeltas == [176, 176, 177, 177, 177, 177])
        #expect(inputValue - outputValue == 1_060)
        #expect(try unsignedTransaction.calculateFee(feePerByte: 1) == 1_060)
        let unsignedTransactionBytes = [UInt8](try unsignedTransaction.encode())
        let signingRequest = try OpalFusion.Host.MosaicTransactionSigningRequest(
            reservationReference: lease.reference,
            roundIdentifier: reservationRequest.roundIdentifier,
            transcriptBinding: try MosaicHostFixture.makeTranscriptBinding(
                profile: profile,
                unsignedTransactionBytes: unsignedTransactionBytes,
                discriminator: 0xA4
            ),
            unsignedTransactionBytes: unsignedTransactionBytes,
            spentInputs: orderedContributions.map(\.participantInput),
            localInputIndices: [localInputIndex],
            expectedLocalOutputs: lease.participantReservation.outputs,
            feeRateSatoshisPerByte: 1,
            minimumExcessFeeSatoshis: 1,
            maximumExcessFeeSatoshis: 2,
            requiredExcessFeeSatoshis: localRequiredExcessFeeSatoshis,
            transactionProfileIdentifier: profile.transactionProfileIdentifier
        )

        let finalized = try await host.finalizeMosaicTransaction(
            for: signingRequest
        )
        let signedTransaction = try OpalBase.Transaction.decode(
            from: Data(finalized.signedFusionTransactionBytes)
        ).transaction
        #expect(
            signedTransaction.inputs.enumerated().filter {
                !$0.element.unlockingScript.isEmpty
            }.map(\.offset) == [localInputIndex]
        )
        #expect(signedTransaction.inputs[localInputIndex].unlockingScript.count == 100)

        var fullySignedTransaction = signedTransaction
        for (index, contribution) in orderedContributions.enumerated()
            where !contribution.isLocal {
            let signingKey = try #require(contribution.signingKey)
            fullySignedTransaction = try fullySignedTransaction.signInputInPlace(
                at: index,
                spending: contribution.unspentOutput,
                signingKey: signingKey,
                signatureFormat: .schnorr,
                unlocker: .p2pkh_CheckSig(
                    hashType: .makeAll(anyoneCanPay: false)
                ),
                using: unsignedTransaction
            )
        }
        let completeTransactionBytes = [UInt8](try fullySignedTransaction.encode())
        #expect(completeTransactionBytes.count == 1_060)
        #expect(
            fullySignedTransaction.inputs.allSatisfy {
                $0.unlockingScript.count == 100 && $0.unlockingScript[65] == 0x41
            }
        )
        let completeTransaction = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: completeTransactionBytes
        )

        try await host.commitMosaicReservation(
            lease.reference,
            completeTransaction: completeTransaction
        )
        try await host.commitMosaicReservation(
            lease.reference,
            completeTransaction: completeTransaction
        )

        #expect(completeTransaction.transactionBytes == completeTransactionBytes)
        #expect(await host.readSigningInvocationCount() == 1)
        #expect(
            Array((await journalProbe.readRecords()).suffix(2)) == [
                .commitIntent(
                    reference: lease.reference,
                    transaction: completeTransaction
                ),
                .committed(
                    reference: lease.reference,
                    transaction: completeTransaction
                )
            ]
        )
        #expect(!(await addressBook.listSpendableUTXOs()).contains(selectedInput))
    }

    @Test("Signing cannot substitute a different valid mainnet alpha fee share")
    func rejectMainnetAlphaSigningShareSubstitution() async throws {
        let profile = OpalFusion.Mosaic.Profile.opalMainnetAlpha
        let network = OpalBase.Network.Environment.mainnet
        let probe = MosaicPolicyProbeActor()
        let policy = await probe.makeTransactionPolicy(
            profile: profile,
            network: network
        )
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            network: network,
            profile: profile
        )
        let lease = try await fixture.reserve()
        let valid = try fixture.makeSigningRequest(lease: lease)
        let substituted = try OpalFusion.Host.MosaicTransactionSigningRequest(
            reservationReference: valid.reservationReference,
            roundIdentifier: valid.roundIdentifier,
            transcriptBinding: valid.transcriptBinding,
            unsignedTransactionBytes: valid.unsignedTransactionBytes,
            spentInputs: valid.spentInputs,
            localInputIndices: valid.localInputIndices,
            expectedLocalOutputs: valid.expectedLocalOutputs,
            feeRateSatoshisPerByte: valid.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: valid.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: valid.maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: 1,
            transactionProfileIdentifier: valid.transactionProfileIdentifier
        )

        await #expect(
            throws: OpalBase.Account.MosaicHostFailure.invalidTransactionProposal
        ) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: substituted)
        }
        #expect(await probe.readInvocationCount() == 0)
        #expect(await fixture.host.readSigningInvocationCount() == 0)
        #expect(await fixture.journalProbe.readRecords().count == 2)

        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test("Only local inputs receive Schnorr ALL|FORKID signatures")
    func signOnlyLocalInputsAndCommitIdempotently() async throws {
        let remote = try await makeRemoteInput(includesPublicKey: false)
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

        let unrelated = try await makeRemoteInput(unhardenedIndex: 2)
        let wrongRemoteKeyTransaction = try locallySigned.signInputInPlace(
            at: 0,
            spending: remote.unspentOutput,
            signingKey: unrelated.signingKey,
            signatureFormat: .schnorr,
            unlocker: .p2pkh_CheckSig(
                hashType: .makeAll(anyoneCanPay: false)
            ),
            using: unsignedTransaction
        )
        let wrongRemoteKey = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: [UInt8](try wrongRemoteKeyTransaction.encode())
        )
        await #expect(throws: OpalBase.Account.MosaicHostFailure.invalidCompleteTransaction) {
            try await fixture.host.commitMosaicReservation(
                lease.reference,
                completeTransaction: wrongRemoteKey
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

private struct SyntheticMainnetAlphaContribution {
    let participantInput: OpalFusion.Host.ParticipantInput
    let transactionInput: OpalBase.Transaction.Input
    let unspentOutput: OpalBase.Transaction.Output.Unspent
    let output: OpalBase.Transaction.Output
    let signingKey: OpalBase.Key.SigningKey?
    let isLocal: Bool
}

private extension AccountMosaicTransactionHostValidator {
    func makeRemoteInput(
        includesPublicKey: Bool = true,
        unhardenedIndex: UInt32 = 1
    ) async throws -> (
        unspentOutput: OpalBase.Transaction.Output.Unspent,
        participantInput: OpalFusion.Host.ParticipantInput,
        signingKey: OpalBase.Key.SigningKey
    ) {
        let account = try await AccountTestFixtures.makeAccount(
            unhardenedIndex: unhardenedIndex
        )
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
                publicKey: includesPublicKey
                    ? [UInt8](signingKey.publicKey.compressedData)
                    : nil
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
            requiredExcessFeeSatoshis: fixture.reservationRequest
                .requiredExcessFeeSatoshis,
            transactionProfileIdentifier: fixture.reservationRequest.transactionProfileIdentifier
        )
    }
}
#endif
