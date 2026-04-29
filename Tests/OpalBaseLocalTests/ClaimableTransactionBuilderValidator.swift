// ClaimableTransactionBuilderValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalBase

@Suite("Claimable transaction builder", .tags(.unit))
struct ClaimableTransactionBuilderValidator {
    @Test("builds claim transaction before expiry")
    func buildsClaimTransactionBeforeExpiry() throws {
        let (envelope, _) = try makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: 50_000
        )
        let destinationLockingScript = makeClaimableDestinationLockingScript(fillByte: 0x55)
        let transaction = try envelope.buildClaimTransaction(
            destinationLockingScript: destinationLockingScript,
            feePerByte: 1,
            currentBlockHeight: 499
        )
        let input = try #require(transaction.inputs.first)
        let output = try #require(transaction.outputs.first)
        let decodedUnlockingScript = try decodeClaimableUnlockingScript(input.unlockingScript)
        let encodedHashType = try #require(decodedUnlockingScript.signatureWithHashType.last)
        let signature = Data(decodedUnlockingScript.signatureWithHashType.dropLast())
        let expectedFee = try transaction.calculateFee(feePerByte: 1)
        let expectedClaimPublicKey = try makeClaimableCompressedPublicKey(
            from: envelope.claimPrivateKey,
            invalidError: .invalidClaimPrivateKey
        )

        #expect(transaction.lockTime == 0)
        #expect(input.sequence == 0xFFFFFFFF)
        #expect(output.lockingScript == destinationLockingScript)
        #expect(output.value == envelope.fundingValue - expectedFee)
        #expect(signature.count == 64)
        #expect(decodedUnlockingScript.publicKey == expectedClaimPublicKey)
        #expect(decodedUnlockingScript.branchOpcode == ScriptOperationCode._1.rawValue)
        #expect(decodedUnlockingScript.redeemScriptData == envelope.contract.redeemScriptData)
        #expect(encodedHashType == UInt8(OpalBase.Transaction.HashType.makeAll().value))
    }

    @Test("claim signature covers redeem script instead of P2SH funding script")
    func claimSignatureCoversRedeemScriptInsteadOfP2SHFundingScript() throws {
        let (envelope, _) = try makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: 50_000
        )
        let transaction = try envelope.buildClaimTransaction(
            destinationLockingScript: makeClaimableDestinationLockingScript(fillByte: 0x55),
            feePerByte: 1,
            currentBlockHeight: 499
        )
        let expectedClaimPublicKey = try makeClaimableCompressedPublicKey(
            from: envelope.claimPrivateKey,
            invalidError: .invalidClaimPrivateKey
        )

        try expectClaimableSignature(
            in: transaction,
            envelope: envelope,
            expectedPublicKey: expectedClaimPublicKey
        )
    }

    @Test("rejects claim transaction at and after expiry")
    func rejectsClaimTransactionAtAndAfterExpiry() throws {
        let (envelope, _) = try makeClaimableEnvelope(expiryBlockHeight: 500)
        let destinationLockingScript = makeClaimableDestinationLockingScript()

        #expect(throws: OpalBase.Claimable.Error.claimRequiresPreExpiry) {
            try envelope.buildClaimTransaction(
                destinationLockingScript: destinationLockingScript,
                currentBlockHeight: 500
            )
        }
        #expect(throws: OpalBase.Claimable.Error.claimRequiresPreExpiry) {
            try envelope.buildClaimTransaction(
                destinationLockingScript: destinationLockingScript,
                currentBlockHeight: 700
            )
        }
    }

    @Test("rejects refund transaction before expiry")
    func rejectsRefundTransactionBeforeExpiry() throws {
        let (envelope, refundPrivateKey) = try makeClaimableEnvelope(expiryBlockHeight: 500)
        let destinationLockingScript = makeClaimableDestinationLockingScript()

        #expect(throws: OpalBase.Claimable.Error.refundRequiresExpiry) {
            try envelope.buildRefundTransaction(
                refundPrivateKey: refundPrivateKey,
                destinationLockingScript: destinationLockingScript,
                currentBlockHeight: 499
            )
        }
    }

    @Test("builds refund transaction at and after expiry")
    func buildsRefundTransactionAtAndAfterExpiry() throws {
        let (envelope, refundPrivateKey) = try makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: 50_000
        )
        let destinationLockingScript = makeClaimableDestinationLockingScript(fillByte: 0x66)
        let transactionAtExpiry = try envelope.buildRefundTransaction(
            refundPrivateKey: refundPrivateKey,
            destinationLockingScript: destinationLockingScript,
            feePerByte: 1,
            currentBlockHeight: 500
        )
        let transactionAfterExpiry = try envelope.buildRefundTransaction(
            refundPrivateKey: refundPrivateKey,
            destinationLockingScript: destinationLockingScript,
            feePerByte: 1,
            currentBlockHeight: 700
        )
        let input = try #require(transactionAtExpiry.inputs.first)
        let decodedUnlockingScript = try decodeClaimableUnlockingScript(input.unlockingScript)
        let expectedRefundPublicKey = try makeClaimableCompressedPublicKey(
            from: refundPrivateKey,
            invalidError: .invalidRefundPrivateKey
        )

        #expect(transactionAtExpiry.lockTime == envelope.contract.expiryBlockHeight)
        #expect(transactionAfterExpiry.lockTime == envelope.contract.expiryBlockHeight)
        #expect(input.sequence == 0xFFFFFFFE)
        #expect(decodedUnlockingScript.branchOpcode == ScriptOperationCode._0.rawValue)
        #expect(decodedUnlockingScript.publicKey == expectedRefundPublicKey)
        #expect(decodedUnlockingScript.redeemScriptData == envelope.contract.redeemScriptData)
    }

    @Test("refund signature covers redeem script instead of P2SH funding script")
    func refundSignatureCoversRedeemScriptInsteadOfP2SHFundingScript() throws {
        let (envelope, refundPrivateKey) = try makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: 50_000
        )
        let transaction = try envelope.buildRefundTransaction(
            refundPrivateKey: refundPrivateKey,
            destinationLockingScript: makeClaimableDestinationLockingScript(fillByte: 0x66),
            feePerByte: 1,
            currentBlockHeight: 500
        )
        let expectedRefundPublicKey = try makeClaimableCompressedPublicKey(
            from: refundPrivateKey,
            invalidError: .invalidRefundPrivateKey
        )

        try expectClaimableSignature(
            in: transaction,
            envelope: envelope,
            expectedPublicKey: expectedRefundPublicKey
        )
    }

    @Test("rejects dust sweep output")
    func rejectsDustSweepOutput() throws {
        let destinationLockingScript = makeClaimableDestinationLockingScript(fillByte: 0x44)
        let (baselineEnvelope, _) = try makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: 50_000
        )
        let baselineTransaction = try baselineEnvelope.buildClaimTransaction(
            destinationLockingScript: destinationLockingScript,
            feePerByte: 1,
            currentBlockHeight: 499
        )
        let fee = try baselineTransaction.calculateFee(feePerByte: 1)
        let dustThreshold = try OpalBase.Transaction.Output(
            value: 1,
            lockingScript: destinationLockingScript
        ).calculateDustThreshold(feeRate: OpalBase.Transaction.minimumRelayFeeRate)
        let (dustEnvelope, _) = try makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: fee + dustThreshold - 1
        )

        #expect(
            throws: OpalBase.Claimable.Error.dustOutput(requiredMinimum: dustThreshold)
        ) {
            try dustEnvelope.buildClaimTransaction(
                destinationLockingScript: destinationLockingScript,
                feePerByte: 1,
                currentBlockHeight: 499
            )
        }
    }

    @Test("rejects funding value that cannot cover the fee")
    func rejectsFundingValueThatCannotCoverTheFee() throws {
        let destinationLockingScript = makeClaimableDestinationLockingScript(fillByte: 0x77)
        let (baselineEnvelope, _) = try makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: 50_000
        )
        let baselineTransaction = try baselineEnvelope.buildClaimTransaction(
            destinationLockingScript: destinationLockingScript,
            feePerByte: 1,
            currentBlockHeight: 499
        )
        let fee = try baselineTransaction.calculateFee(feePerByte: 1)
        let (insufficientEnvelope, _) = try makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: fee
        )

        #expect(
            throws: OpalBase.Claimable.Error.insufficientFundingValue(required: fee + 1)
        ) {
            try insufficientEnvelope.buildClaimTransaction(
                destinationLockingScript: destinationLockingScript,
                feePerByte: 1,
                currentBlockHeight: 499
            )
        }
    }

    private func expectClaimableSignature(
        in transaction: OpalBase.Transaction,
        envelope: OpalBase.Claimable.Envelope,
        expectedPublicKey: Data
    ) throws {
        let input = try #require(transaction.inputs.first)
        let decodedUnlockingScript = try decodeClaimableUnlockingScript(input.unlockingScript)
        let signatureWithHashType = decodedUnlockingScript.signatureWithHashType
        let signature = try #require(
            signatureWithHashType.dropLast().isEmpty
                ? nil
                : Data(signatureWithHashType.dropLast())
        )
        let encodedHashType = try #require(signatureWithHashType.last)
        let hashType = OpalBase.Transaction.HashType.makeAll(anyoneCanPay: false)
        let redeemScriptOutput = OpalBase.Transaction.Output(
            value: envelope.fundingValue,
            lockingScript: envelope.contract.redeemScriptData
        )
        let fundingLockingScriptOutput = OpalBase.Transaction.Output(
            value: envelope.fundingValue,
            lockingScript: envelope.contract.fundingLockingScriptData
        )
        let redeemScriptPreimage = try transaction.generatePreimage(
            for: 0,
            hashType: hashType,
            outputBeingSpent: redeemScriptOutput
        )
        let fundingLockingScriptPreimage = try transaction.generatePreimage(
            for: 0,
            hashType: hashType,
            outputBeingSpent: fundingLockingScriptOutput
        )
        let isValidAgainstRedeemScript = try OpalCrypto.Signature.verifySchnorr(
            signature: signature,
            digest: OpalCrypto.Hashing.computeHash256(redeemScriptPreimage),
            publicKey: decodedUnlockingScript.publicKey
        )
        let isValidAgainstFundingLockingScript = try OpalCrypto.Signature.verifySchnorr(
            signature: signature,
            digest: OpalCrypto.Hashing.computeHash256(fundingLockingScriptPreimage),
            publicKey: decodedUnlockingScript.publicKey
        )

        #expect(encodedHashType == UInt8(truncatingIfNeeded: hashType.value))
        #expect(signature.count == 64)
        #expect(decodedUnlockingScript.publicKey == expectedPublicKey)
        #expect(envelope.contract.redeemScriptData != envelope.contract.fundingLockingScriptData)
        #expect(isValidAgainstRedeemScript)
        #expect(!isValidAgainstFundingLockingScript)
    }
}
