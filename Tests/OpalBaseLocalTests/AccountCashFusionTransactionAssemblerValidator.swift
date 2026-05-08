#if os(macOS)
// AccountCashFusionTransactionAssemblerValidator.swift

import Foundation
import OpalCrypto
import OpalFusion
import Testing
@testable import OpalBase

@Suite("OpalBase.Account CashFusion transaction finalization", .tags(.unit, .wallet, .transaction))
struct AccountCashFusionTransactionAssemblerValidator {
    @Test("valid unsigned proposal is signed in place and returned as finalized bytes")
    func validUnsignedProposalIsSignedInPlaceAndReturnedAsFinalizedBytes() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let firstInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 150_000,
            usage: .change,
            hashByte: 0xC1
        )
        let secondInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 160_000,
            usage: .change,
            hashByte: 0xC2
        )
        let reservation = try await account.prepareCashFusionReservation(
            request: .init(
                selectedInputs: [firstInput, secondInput],
                outputAmounts: [try OpalBase.Satoshi(60_000)]
            )
        )
        let assembler = OpalBase.Account.CashFusionTransactionAssembler(
            reservation: reservation
        )
        let remoteInput = OpalBase.Transaction.Input(
            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0xC3),
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let unsignedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: firstInput.previousTransactionHash,
                    previousTransactionOutputIndex: firstInput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                ),
                remoteInput,
                .init(
                    previousTransactionHash: secondInput.previousTransactionHash,
                    previousTransactionOutputIndex: secondInput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                )
            ],
            outputs: [
                .init(value: 90_000, lockingScript: Data([0x51])),
                .init(value: 120_000, lockingScript: Data([0x52]))
            ],
            lockTime: 0
        )

        let finalized = try await assembler.finalizeTransaction(
            for: .init(rawValue: "round-success"),
            proposal: CashFusionTestSupport.makeProposal(transaction: unsignedTransaction)
        )
        let decoded = try OpalBase.Transaction.decode(
            from: Data(finalized.transactionBytes)
        ).transaction

        #expect(decoded.outputs == unsignedTransaction.outputs)
        #expect(decoded.inputs[1].unlockingScript.isEmpty)
        #expect(decoded.inputs[0].unlockingScript.isEmpty == false)
        #expect(decoded.inputs[2].unlockingScript.isEmpty == false)

        try await reservation.cancel()
    }

    @Test("reordered local inputs are signed by matched outpoint")
    func reorderedLocalInputsAreSignedByMatchedOutpoint() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let firstInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 120_000,
            usage: .change,
            hashByte: 0xC4
        )
        let secondInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 130_000,
            usage: .change,
            hashByte: 0xC5
        )
        let reservation = try await account.prepareCashFusionReservation(
            request: .init(
                selectedInputs: [firstInput, secondInput],
                outputAmounts: [try OpalBase.Satoshi(55_000)]
            )
        )
        let assembler = OpalBase.Account.CashFusionTransactionAssembler(
            reservation: reservation
        )
        let remoteInput = OpalBase.Transaction.Input(
            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0xD4),
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let reorderedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: secondInput.previousTransactionHash,
                    previousTransactionOutputIndex: secondInput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                ),
                remoteInput,
                .init(
                    previousTransactionHash: firstInput.previousTransactionHash,
                    previousTransactionOutputIndex: firstInput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                )
            ],
            outputs: [.init(value: 80_000, lockingScript: Data([0x51]))],
            lockTime: 0
        )

        let finalized = try await assembler.finalizeTransaction(
            for: .init(rawValue: "round-reordered"),
            proposal: CashFusionTestSupport.makeProposal(transaction: reorderedTransaction)
        )
        let decoded = try OpalBase.Transaction.decode(
            from: Data(finalized.transactionBytes)
        ).transaction
        let firstReservedInput = try #require(reservation.reservedInputs.first)
        let secondReservedInput = try #require(reservation.reservedInputs.dropFirst().first)
        let firstLocalUnlockingScript = try decodeCashFusionP2PKHUnlockingScript(
            decoded.inputs[0].unlockingScript
        )
        let secondLocalUnlockingScript = try decodeCashFusionP2PKHUnlockingScript(
            decoded.inputs[2].unlockingScript
        )

        #expect(decoded.outputs == reorderedTransaction.outputs)
        #expect(decoded.inputs[1].unlockingScript.isEmpty)
        #expect(firstLocalUnlockingScript.publicKey == secondReservedInput.compressedPublicKey)
        #expect(secondLocalUnlockingScript.publicKey == firstReservedInput.compressedPublicKey)

        try await reservation.cancel()
    }

    @Test("mismatched local inputs are rejected as transaction assembly failures")
    func mismatchedLocalInputsAreRejectedAsTransactionAssemblyFailures() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let firstInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 120_000,
            usage: .change,
            hashByte: 0xD5
        )
        let secondInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 130_000,
            usage: .change,
            hashByte: 0xD6
        )
        let reservation = try await account.prepareCashFusionReservation(
            request: .init(
                selectedInputs: [firstInput, secondInput],
                outputAmounts: [try OpalBase.Satoshi(55_000)]
            )
        )
        let assembler = OpalBase.Account.CashFusionTransactionAssembler(
            reservation: reservation
        )
        let mismatchedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: firstInput.previousTransactionHash,
                    previousTransactionOutputIndex: firstInput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                )
            ],
            outputs: [.init(value: 80_000, lockingScript: Data([0x51]))],
            lockTime: 0
        )

        await #expect(
            throws: OpalFusion.Host.TransactionFinalizationFailure.transactionAssemblyFailed(
                summary: "CashFusion transaction assembly failed"
            )
        ) {
            _ = try await assembler.finalizeTransaction(
                for: .init(rawValue: "round-mismatched"),
                proposal: CashFusionTestSupport.makeProposal(transaction: mismatchedTransaction)
            )
        }

        try await reservation.cancel()
    }

    @Test("proposal transaction count mismatches are rejected before signing")
    func proposalTransactionCountMismatchesAreRejectedBeforeSigning() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 130_000,
            usage: .change,
            hashByte: 0xC7
        )
        let reservation = try await account.prepareCashFusionReservation(
            request: .init(
                selectedInputs: [selectedInput],
                outputAmounts: [try OpalBase.Satoshi(50_000)]
            )
        )
        let assembler = OpalBase.Account.CashFusionTransactionAssembler(
            reservation: reservation
        )
        let unsignedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: selectedInput.previousTransactionHash,
                    previousTransactionOutputIndex: selectedInput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                )
            ],
            outputs: [.init(value: 80_000, lockingScript: Data([0x51]))],
            lockTime: 0
        )
        let unsignedTransactionBytes = [UInt8](try unsignedTransaction.encode())

        await #expect(
            throws: OpalFusion.Host.TransactionFinalizationFailure.transactionAssemblyFailed(
                summary: "CashFusion transaction assembly failed"
            )
        ) {
            _ = try await assembler.finalizeTransaction(
                for: .init(rawValue: "round-input-count"),
                proposal: .init(
                    unsignedTransactionBytes: unsignedTransactionBytes,
                    expectedInputCount: 2,
                    expectedOutputCount: 1
                )
            )
        }

        await #expect(
            throws: OpalFusion.Host.TransactionFinalizationFailure.transactionAssemblyFailed(
                summary: "CashFusion transaction assembly failed"
            )
        ) {
            _ = try await assembler.finalizeTransaction(
                for: .init(rawValue: "round-output-count"),
                proposal: .init(
                    unsignedTransactionBytes: unsignedTransactionBytes,
                    expectedInputCount: 1,
                    expectedOutputCount: 2
                )
            )
        }

        try await reservation.cancel()
    }

    @Test("reservation policy refusals are reported as host policy failures")
    func reservationPolicyRefusalsAreReportedAsHostPolicyFailures() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 150_000,
            usage: .change,
            hashByte: 0xD7
        )
        let reservation = try await account.prepareCashFusionReservation(
            request: .init(
                selectedInputs: [selectedInput],
                outputPolicy: .valuePreserving
            )
        )
        let assembler = OpalBase.Account.CashFusionTransactionAssembler(
            reservation: reservation
        )
        let unsignedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: selectedInput.previousTransactionHash,
                    previousTransactionOutputIndex: selectedInput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                )
            ],
            outputs: [.init(value: 80_000, lockingScript: Data([0x51]))],
            lockTime: 0
        )

        await #expect(
            throws: OpalFusion.Host.TransactionFinalizationFailure.hostPolicyRejected(
                summary: "CashFusion host policy rejected transaction"
            )
        ) {
            _ = try await assembler.finalizeTransaction(
                for: .init(rawValue: "round-policy-refusal"),
                proposal: CashFusionTestSupport.makeProposal(transaction: unsignedTransaction)
            )
        }

        try await reservation.cancel()
    }

    @Test("finalized unlocking scripts use the standard Schnorr P2PKH form")
    func finalizedUnlockingScriptsUseTheStandardSchnorrP2PKHForm() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await CashFusionTestSupport.makeWalletOwnedUnspentOutput(
            to: account,
            value: 140_000,
            usage: .change,
            hashByte: 0xC6
        )
        let reservation = try await account.prepareCashFusionReservation(
            request: .init(
                selectedInputs: [selectedInput],
                outputAmounts: [try OpalBase.Satoshi(45_000)]
            )
        )
        let assembler = OpalBase.Account.CashFusionTransactionAssembler(
            reservation: reservation
        )
        let unsignedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: selectedInput.previousTransactionHash,
                    previousTransactionOutputIndex: selectedInput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                )
            ],
            outputs: [.init(value: 70_000, lockingScript: Data([0x51]))],
            lockTime: 0
        )

        let finalized = try await assembler.finalizeTransaction(
            for: .init(rawValue: "round-schnorr"),
            proposal: CashFusionTestSupport.makeProposal(transaction: unsignedTransaction)
        )
        let decoded = try OpalBase.Transaction.decode(
            from: Data(finalized.transactionBytes)
        ).transaction
        let unlockingScript = try decodeCashFusionP2PKHUnlockingScript(
            decoded.inputs[0].unlockingScript
        )
        let reservedInput = try #require(reservation.reservedInputs.first)
        let signature = try #require(
            unlockingScript.signatureWithHashType.dropLast().isEmpty
            ? nil
            : Data(unlockingScript.signatureWithHashType.dropLast())
        )
        let hashType = try #require(unlockingScript.signatureWithHashType.last)
        let outputBeingSpent = OpalBase.Transaction.Output(
            value: selectedInput.value,
            lockingScript: selectedInput.lockingScript,
            tokenData: selectedInput.tokenData
        )
        let preimage = try decoded.generatePreimage(
            for: 0,
            hashType: .makeAll(anyoneCanPay: false),
            outputBeingSpent: outputBeingSpent
        )
        let isValid = try OpalCrypto.Signature.Schnorr(rawRepresentation: signature).verify(
            digest: OpalCrypto.Signature.Digest(rawRepresentation: OpalCrypto.Hashing.hash256(preimage)),
            publicKey: OpalCrypto.Secp256k1.PublicKey(rawRepresentation: unlockingScript.publicKey)
        )

        #expect(hashType == UInt8(truncatingIfNeeded: OpalBase.Transaction.HashType.makeAll().value))
        #expect(signature.count == 64)
        #expect(unlockingScript.publicKey == reservedInput.compressedPublicKey)
        #expect(isValid)

        try await reservation.cancel()
    }
}
#endif
