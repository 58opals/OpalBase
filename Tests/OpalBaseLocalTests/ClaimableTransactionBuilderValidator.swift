// ClaimableTransactionBuilderValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalBase

@Suite("Claimable transaction builder", .tags(.unit))
struct ClaimableTransactionBuilderValidator {
    @Test("builds claim transaction before expiry")
    func buildsClaimTransactionBeforeExpiry() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: 50_000
        )
        let destinationLockingScript = ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x55)
        let transaction = try envelope.buildClaimTransaction(
            destinationLockingScript: destinationLockingScript,
            feePerByte: 1,
            currentBlockHeight: 499
        )
        let input = try #require(transaction.inputs.first)
        let output = try #require(transaction.outputs.first)
        let decodedUnlockingScript = try ClaimableTestSupport.decodeClaimableUnlockingScript(input.unlockingScript)
        let encodedHashType = try #require(decodedUnlockingScript.signatureWithHashType.last)
        let signature = Data(decodedUnlockingScript.signatureWithHashType.dropLast())
        let expectedFee = try transaction.calculateFee(feePerByte: 1)
        let expectedClaimPublicKey = try ClaimablePrimitiveOperation.makeCompressedPublicKey(
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

    @Test("rejects claim transaction at and after expiry", arguments: [UInt32(500), UInt32(700)])
    func rejectsClaimTransactionAtAndAfterExpiry(currentBlockHeight: UInt32) throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(expiryBlockHeight: 500)
        let destinationLockingScript = ClaimableTestSupport.makeClaimableDestinationLockingScript()

        #expect(throws: OpalBase.Claimable.Error.claimRequiresPreExpiry) {
            try envelope.buildClaimTransaction(
                destinationLockingScript: destinationLockingScript,
                currentBlockHeight: currentBlockHeight
            )
        }
    }

    @Test(
        "rejects refund transaction before expiry",
        arguments: RefundCredentialCase.allCases
    )
    func rejectsRefundTransactionBeforeExpiry(
        _ credentialCase: RefundCredentialCase
    ) throws {
        let (envelope, refundPrivateKey) = try ClaimableTestSupport.makeClaimableEnvelope(expiryBlockHeight: 500)
        let destinationLockingScript = ClaimableTestSupport.makeClaimableDestinationLockingScript()

        #expect(throws: OpalBase.Claimable.Error.refundRequiresExpiry) {
            try credentialCase.buildRefundTransaction(
                envelope: envelope,
                refundPrivateKey: refundPrivateKey,
                destinationLockingScript: destinationLockingScript,
                currentBlockHeight: 499
            )
        }
    }

    @Test("rejects raw refund transaction before expiry before parsing key")
    func rejectsRawRefundTransactionBeforeExpiryBeforeParsingKey() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(expiryBlockHeight: 500)
        let destinationLockingScript = ClaimableTestSupport.makeClaimableDestinationLockingScript()
        let invalidRefundPrivateKey = Data(repeating: 0x01, count: 31)

        #expect(throws: OpalBase.Claimable.Error.refundRequiresExpiry) {
            try envelope.buildRefundTransaction(
                refundPrivateKey: invalidRefundPrivateKey,
                destinationLockingScript: destinationLockingScript,
                currentBlockHeight: 499
            )
        }
    }

    @Test("rejects refund invalid destination before parsing raw key")
    func rejectsRefundInvalidDestinationBeforeParsingRawKey() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: 50_000
        )
        let invalidRefundPrivateKey = Data(repeating: 0x01, count: 31)

        #expect(throws: OpalBase.Claimable.Error.invalidDestinationOutput) {
            try envelope.buildRefundTransaction(
                refundPrivateKey: invalidRefundPrivateKey,
                destinationLockingScript: Data([ScriptOperationCode._RETURN.rawValue]),
                feePerByte: 1,
                currentBlockHeight: 500
            )
        }
    }

    @Test("builds refund transaction at and after expiry", arguments: RefundBuildCase.allCases)
    func buildsRefundTransactionAtAndAfterExpiry(_ refundBuildCase: RefundBuildCase) throws {
        let (envelope, refundPrivateKey) = try ClaimableTestSupport.makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: 50_000
        )
        let destinationLockingScript = ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x66)
        let transaction = try refundBuildCase.credentialCase.buildRefundTransaction(
            envelope: envelope,
            refundPrivateKey: refundPrivateKey,
            destinationLockingScript: destinationLockingScript,
            feePerByte: 1,
            currentBlockHeight: refundBuildCase.currentBlockHeight
        )
        let input = try #require(transaction.inputs.first)
        let decodedUnlockingScript = try ClaimableTestSupport.decodeClaimableUnlockingScript(input.unlockingScript)
        let expectedRefundPublicKey = try ClaimablePrimitiveOperation.makeCompressedPublicKey(
            from: refundPrivateKey,
            invalidError: .invalidRefundPrivateKey
        )

        #expect(transaction.lockTime == envelope.contract.expiryBlockHeight)
        #expect(input.sequence == 0xFFFFFFFE)
        #expect(decodedUnlockingScript.branchOpcode == ScriptOperationCode._0.rawValue)
        #expect(decodedUnlockingScript.publicKey == expectedRefundPublicKey)
        #expect(decodedUnlockingScript.redeemScriptData == envelope.contract.redeemScriptData)
    }

    @Test("builds refund transaction with scoped refund signing key")
    func buildsRefundTransactionWithScopedRefundSigningKey() throws {
        let (envelope, refundPrivateKey) = try ClaimableTestSupport.makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: 50_000
        )
        let refundSigningKey = try OpalBase.Key.SigningKey(rawRepresentation: refundPrivateKey)
        let destinationLockingScript = ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x67)
        let rawKeyTransaction = try envelope.buildRefundTransaction(
            refundPrivateKey: refundPrivateKey,
            destinationLockingScript: destinationLockingScript,
            feePerByte: 1,
            currentBlockHeight: 500
        )
        let signingKeyTransaction = try envelope.buildRefundTransaction(
            refundSigningKey: refundSigningKey,
            destinationLockingScript: destinationLockingScript,
            feePerByte: 1,
            currentBlockHeight: 500
        )

        #expect(try signingKeyTransaction.encode() == rawKeyTransaction.encode())
    }

    @Test("claimable signatures cover redeem script instead of P2SH funding script", arguments: ClaimableSignaturePathCase.allCases)
    fileprivate func claimableSignaturesCoverRedeemScriptInsteadOfP2SHFundingScript(_ signaturePathCase: ClaimableSignaturePathCase) throws {
        let (envelope, refundPrivateKey) = try ClaimableTestSupport.makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: 50_000
        )
        let transaction = try signaturePathCase.buildTransaction(
            envelope: envelope,
            refundPrivateKey: refundPrivateKey
        )
        let expectedPublicKey = try signaturePathCase.makeExpectedPublicKey(
            envelope: envelope,
            refundPrivateKey: refundPrivateKey
        )

        try expectClaimableSignature(
            in: transaction,
            envelope: envelope,
            expectedPublicKey: expectedPublicKey
        )
    }

    @Test("rejects dust sweep output")
    func rejectsDustSweepOutput() throws {
        let destinationLockingScript = ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x44)
        let (baselineEnvelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
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
        let (dustEnvelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
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
    
    @Test("rejects unspendable OP_RETURN sweep outputs")
    func rejectsUnspendableOpReturnSweepOutputs() throws {
        let (envelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: 50_000
        )
        
        #expect(throws: OpalBase.Claimable.Error.invalidDestinationOutput) {
            try envelope.buildClaimTransaction(
                destinationLockingScript: Data([ScriptOperationCode._RETURN.rawValue]),
                feePerByte: 1,
                currentBlockHeight: 499
            )
        }
    }

    @Test("rejects funding value that cannot cover the fee")
    func rejectsFundingValueThatCannotCoverTheFee() throws {
        let destinationLockingScript = ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x77)
        let (baselineEnvelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
            expiryBlockHeight: 500,
            fundingValue: 50_000
        )
        let baselineTransaction = try baselineEnvelope.buildClaimTransaction(
            destinationLockingScript: destinationLockingScript,
            feePerByte: 1,
            currentBlockHeight: 499
        )
        let fee = try baselineTransaction.calculateFee(feePerByte: 1)
        let (insufficientEnvelope, _) = try ClaimableTestSupport.makeClaimableEnvelope(
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
        let decodedUnlockingScript = try ClaimableTestSupport.decodeClaimableUnlockingScript(input.unlockingScript)
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
        let schnorrSignature = try OpalCrypto.Signature.Schnorr(rawRepresentation: signature)
        let publicKey = try OpalCrypto.Secp256k1.PublicKey(rawRepresentation: decodedUnlockingScript.publicKey)
        let isValidAgainstRedeemScript = try schnorrSignature.verify(
            digest: OpalCrypto.Signature.Digest(rawRepresentation: OpalCrypto.Hashing.hash256(redeemScriptPreimage)),
            publicKey: publicKey
        )
        let isValidAgainstFundingLockingScript = try schnorrSignature.verify(
            digest: OpalCrypto.Signature.Digest(rawRepresentation: OpalCrypto.Hashing.hash256(fundingLockingScriptPreimage)),
            publicKey: publicKey
        )

        #expect(encodedHashType == UInt8(truncatingIfNeeded: hashType.value))
        #expect(signature.count == 64)
        #expect(decodedUnlockingScript.publicKey == expectedPublicKey)
        #expect(envelope.contract.redeemScriptData != envelope.contract.fundingLockingScriptData)
        #expect(isValidAgainstRedeemScript)
        #expect(!isValidAgainstFundingLockingScript)
    }

    enum RefundCredentialCase: CaseIterable, CustomStringConvertible, Sendable {
        case rawPrivateKey
        case signingKey

        var description: String {
            switch self {
            case .rawPrivateKey:
                "raw private key"
            case .signingKey:
                "signing key"
            }
        }

        func buildRefundTransaction(
            envelope: OpalBase.Claimable.Envelope,
            refundPrivateKey: Data,
            destinationLockingScript: Data,
            feePerByte: UInt64 = OpalBase.Transaction.defaultFeeRate,
            currentBlockHeight: UInt32
        ) throws -> OpalBase.Transaction {
            switch self {
            case .rawPrivateKey:
                try envelope.buildRefundTransaction(
                    refundPrivateKey: refundPrivateKey,
                    destinationLockingScript: destinationLockingScript,
                    feePerByte: feePerByte,
                    currentBlockHeight: currentBlockHeight
                )
            case .signingKey:
                try envelope.buildRefundTransaction(
                    refundSigningKey: OpalBase.Key.SigningKey(rawRepresentation: refundPrivateKey),
                    destinationLockingScript: destinationLockingScript,
                    feePerByte: feePerByte,
                    currentBlockHeight: currentBlockHeight
                )
            }
        }
    }

    struct RefundBuildCase: CaseIterable, CustomStringConvertible, Sendable {
        let credentialCase: RefundCredentialCase
        let currentBlockHeight: UInt32

        static let allCases = RefundCredentialCase.allCases.flatMap { credentialCase in
            [UInt32(500), UInt32(700)].map { currentBlockHeight in
                Self(credentialCase: credentialCase, currentBlockHeight: currentBlockHeight)
            }
        }

        var description: String {
            "\(credentialCase) at height \(currentBlockHeight)"
        }
    }

    enum ClaimableSignaturePathCase: CaseIterable, CustomStringConvertible, Sendable {
        case claim
        case refund(RefundCredentialCase)

        static let allCases: [Self] = [.claim] + RefundCredentialCase.allCases.map(Self.refund)

        var description: String {
            switch self {
            case .claim:
                "claim"
            case .refund(let credentialCase):
                "refund with \(credentialCase)"
            }
        }

        func buildTransaction(
            envelope: OpalBase.Claimable.Envelope,
            refundPrivateKey: Data
        ) throws -> OpalBase.Transaction {
            switch self {
            case .claim:
                try envelope.buildClaimTransaction(
                    destinationLockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x55),
                    feePerByte: 1,
                    currentBlockHeight: 499
                )
            case .refund(let credentialCase):
                try credentialCase.buildRefundTransaction(
                    envelope: envelope,
                    refundPrivateKey: refundPrivateKey,
                    destinationLockingScript: ClaimableTestSupport.makeClaimableDestinationLockingScript(fillByte: 0x66),
                    feePerByte: 1,
                    currentBlockHeight: 500
                )
            }
        }

        func makeExpectedPublicKey(
            envelope: OpalBase.Claimable.Envelope,
            refundPrivateKey: Data
        ) throws -> Data {
            switch self {
            case .claim:
                try ClaimablePrimitiveOperation.makeCompressedPublicKey(
                    from: envelope.claimPrivateKey,
                    invalidError: .invalidClaimPrivateKey
                )
            case .refund:
                try ClaimablePrimitiveOperation.makeCompressedPublicKey(
                    from: refundPrivateKey,
                    invalidError: .invalidRefundPrivateKey
                )
            }
        }
    }
}
