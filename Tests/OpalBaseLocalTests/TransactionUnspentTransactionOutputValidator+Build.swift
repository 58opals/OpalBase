// TransactionUnspentTransactionOutputValidator+Build.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalBase

extension TransactionUnspentTransactionOutputValidator {
    @Test("build rejects empty input set")
    func buildRejectsEmptyInputSet() throws {
        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            _ = try OpalBase.Transaction.build(
                utxoPrivateKeyPairs: [:],
                recipientOutputs: [],
                changeOutput: OpalBase.Transaction.Output(value: 10_000, lockingScript: Data([0x51])),
                feePerByte: 0,
                privacyOutputShuffle: { $0 }
            )
        }
    }

    @Test("unsigned envelope rejects empty input set")
    func unsignedEnvelopeRejectsEmptyInputSet() throws {
        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            _ = try OpalBase.Transaction.makeUnsignedTransactionEnvelope(
                unspentOutputs: [],
                recipientOutputs: [],
                changeOutput: OpalBase.Transaction.Output(value: 10_000, lockingScript: Data([0x51])),
                feePerByte: 0,
                privacyOutputShuffle: { $0 }
            )
        }
    }

    @Test("unsigned envelope rejects duplicate input set")
    func unsignedEnvelopeRejectsDuplicateInputSet() throws {
        let components = try makeTransactionBuilderComponents()
        let unspent = try #require(components.privateKeys.keys.first)

        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            _ = try OpalBase.Transaction.makeUnsignedTransactionEnvelope(
                unspentOutputs: [unspent, unspent],
                recipientOutputs: components.recipientOutputs,
                changeOutput: components.changeOutput,
                feePerByte: 0,
                privacyOutputShuffle: { $0 }
            )
        }
    }

    @Test("unsigned envelope rejects unsupported signature format before empty input set")
    func unsignedEnvelopeRejectsUnsupportedSignatureFormatBeforeEmptyInputSet() throws {
        #expect(throws: OpalBase.Transaction.Error.unsupportedSignatureFormat) {
            _ = try OpalBase.Transaction.makeUnsignedTransactionEnvelope(
                unspentOutputs: [],
                recipientOutputs: [],
                changeOutput: OpalBase.Transaction.Output(value: 10_000, lockingScript: Data([0x51])),
                signatureFormat: .ecdsa(.raw),
                feePerByte: 0,
                privacyOutputShuffle: { $0 }
            )
        }
    }

    @Test("raw private-key build accepts sliced private keys")
    func rawPrivateKeyBuildAcceptsSlicedPrivateKeys() throws {
        let components = try makeTransactionBuilderComponents()
        let unspent = try #require(components.privateKeys.keys.first)
        let privateKey = Data(repeating: 0x02, count: 32)
        let paddedPrivateKey = Data([0x00]) + privateKey
        let slicedPrivateKey = paddedPrivateKey[
            paddedPrivateKey.index(after: paddedPrivateKey.startIndex)...
        ]

        let transaction = try OpalBase.Transaction.build(
            utxoPrivateKeyPairs: [unspent: slicedPrivateKey],
            recipientOutputs: components.recipientOutputs,
            changeOutput: components.changeOutput,
            outputOrderingStrategy: .privacyRandomized,
            signatureFormat: .schnorr,
            feePerByte: 0,
            privacyOutputShuffle: { $0 }
        )
        let input = try #require(transaction.inputs.first)
        let decodedUnlockingScript = try decodeP2PKHUnlockingScript(input.unlockingScript)
        let expectedPublicKey = try OpalBase.Key.PublicKey(privateKeyData: privateKey)

        #expect(slicedPrivateKey.startIndex != privateKey.startIndex)
        #expect(input.unlockingScript.isEmpty == false)
        #expect(decodedUnlockingScript.publicKey == expectedPublicKey.compressedData)
    }

    @Test("raw private-key build rejects unsupported signature format before parsing keys")
    func rawPrivateKeyBuildRejectsUnsupportedSignatureFormatBeforeParsingKeys() throws {
        let components = try makeTransactionBuilderComponents()
        let unspent = try #require(components.privateKeys.keys.first)
        let invalidPrivateKeys = [unspent: Data(repeating: 0x01, count: 31)]

        #expect(throws: OpalBase.Transaction.Error.unsupportedSignatureFormat) {
            _ = try OpalBase.Transaction.build(
                utxoPrivateKeyPairs: invalidPrivateKeys,
                recipientOutputs: components.recipientOutputs,
                changeOutput: components.changeOutput,
                signatureFormat: .ecdsa(.raw),
                feePerByte: 0,
                privacyOutputShuffle: { $0 }
            )
        }
    }

    @Test("raw private-key build rejects unsupported hash type before parsing keys")
    func rawPrivateKeyBuildRejectsUnsupportedHashTypeBeforeParsingKeys() throws {
        let components = try makeTransactionBuilderComponents()
        let unspent = try #require(components.privateKeys.keys.first)
        let invalidPrivateKeys = [unspent: Data(repeating: 0x01, count: 31)]
        let unsupportedHashType = OpalBase.Transaction.HashType.makeAll(
            anyoneCanPay: true,
            includesUnspentTransactionOutputs: true
        )

        #expect(throws: OpalBase.Transaction.Error.unsupportedHashType) {
            _ = try OpalBase.Transaction.build(
                utxoPrivateKeyPairs: invalidPrivateKeys,
                recipientOutputs: components.recipientOutputs,
                changeOutput: components.changeOutput,
                signatureFormat: .schnorr,
                feePerByte: 0,
                privacyOutputShuffle: { $0 },
                unlockers: [unspent: .p2pkh_CheckSig(hashType: unsupportedHashType)]
            )
        }
    }

    @Test("raw private-key build rejects unselected unlockers before parsing keys")
    func rawPrivateKeyBuildRejectsUnselectedUnlockersBeforeParsingKeys() throws {
        let components = try makeTransactionBuilderComponents()
        let selectedUnspent = try #require(components.privateKeys.keys.first)
        let invalidPrivateKeys = [selectedUnspent: Data(repeating: 0x01, count: 31)]
        let unselectedUnspent = OpalBase.Transaction.Output.Unspent(
            value: selectedUnspent.value,
            lockingScript: selectedUnspent.lockingScript,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x7B, count: 32)),
            previousTransactionOutputIndex: selectedUnspent.previousTransactionOutputIndex
        )

        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            _ = try OpalBase.Transaction.build(
                utxoPrivateKeyPairs: invalidPrivateKeys,
                recipientOutputs: components.recipientOutputs,
                changeOutput: components.changeOutput,
                signatureFormat: .schnorr,
                feePerByte: 0,
                privacyOutputShuffle: { $0 },
                unlockers: [
                    unselectedUnspent: .p2pkh_CheckDataSig(message: Data([0x01]))
                ]
            )
        }
    }

    @Test(
        "transaction builders reject unlockers for unselected inputs",
        arguments: UnselectedUnlockerBoundaryCase.allCases
    )
    func transactionBuildersRejectUnlockersForUnselectedInputs(
        _ boundaryCase: UnselectedUnlockerBoundaryCase
    ) throws {
        let components = try makeTransactionBuilderComponents()
        let selectedUnspent = try #require(components.privateKeys.keys.first)
        let unselectedUnspent = OpalBase.Transaction.Output.Unspent(
            value: selectedUnspent.value,
            lockingScript: selectedUnspent.lockingScript,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x7A, count: 32)),
            previousTransactionOutputIndex: selectedUnspent.previousTransactionOutputIndex
        )

        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            switch boundaryCase {
            case .signedBuild:
                _ = try OpalBase.Transaction.build(
                    utxoPrivateKeyPairs: components.privateKeys,
                    recipientOutputs: components.recipientOutputs,
                    changeOutput: components.changeOutput,
                    outputOrderingStrategy: .privacyRandomized,
                    signatureFormat: .schnorr,
                    feePerByte: 0,
                    privacyOutputShuffle: { $0 },
                    unlockers: [
                        unselectedUnspent: .p2pkh_CheckDataSig(message: Data([0x01]))
                    ]
                )
            case .unsignedEnvelope:
                _ = try OpalBase.Transaction.makeUnsignedTransactionEnvelope(
                    unspentOutputs: [selectedUnspent],
                    recipientOutputs: components.recipientOutputs,
                    changeOutput: components.changeOutput,
                    outputOrderingStrategy: .privacyRandomized,
                    signatureFormat: .schnorr,
                    feePerByte: 0,
                    privacyOutputShuffle: { $0 },
                    unlockers: [
                        unselectedUnspent: .p2pkh_CheckDataSig(message: Data([0x01]))
                    ]
                )
            }
        }
    }

    @Test("raw private-key signing rejects missing target input before parsing key")
    func rawPrivateKeySigningRejectsMissingTargetInputBeforeParsingKey() throws {
        let fixture = makeRawPrivateKeySigningValidationFixture()
        let transactionWithoutInputs = OpalBase.Transaction(
            version: fixture.transaction.version,
            inputs: [],
            outputs: fixture.transaction.outputs,
            lockTime: fixture.transaction.lockTime
        )

        #expect(throws: OpalBase.Transaction.Error.sighashSingleIndexOutOfRange) {
            try transactionWithoutInputs.signInputInPlace(
                at: 0,
                spending: fixture.outputBeingSpent,
                privateKey: fixture.invalidPrivateKey,
                signatureFormat: .schnorr,
                unlocker: .p2pkh_CheckSig(),
                using: fixture.transaction
            )
        }
    }

    @Test(
        "signing rejects mismatched template",
        arguments: SigningTemplateMismatchCase.allCases
    )
    func signingRejectsMismatchedTemplate(
        _ mismatchCase: SigningTemplateMismatchCase
    ) throws {
        let fixture = makeRawPrivateKeySigningValidationFixture()
        let mismatchedTemplate = mismatchCase.makeMismatchedTemplate(from: fixture.transaction)

        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            try mismatchCase.sign(
                transaction: fixture.transaction,
                outputBeingSpent: fixture.outputBeingSpent,
                invalidPrivateKey: fixture.invalidPrivateKey,
                using: mismatchedTemplate
            )
        }
    }

    @Test(
        "raw private-key signing rejects spent-output shape before parsing key",
        arguments: RawPrivateKeySigningSpentOutputShapeCase.allCases
    )
    func rawPrivateKeySigningRejectsSpentOutputShapeBeforeParsingKey(
        _ shapeCase: RawPrivateKeySigningSpentOutputShapeCase
    ) throws {
        let fixture = makeRawPrivateKeySigningValidationFixture()
        let hashType = OpalBase.Transaction.HashType.makeAll(includesUnspentTransactionOutputs: true)

        #expect(throws: shapeCase.expectedError) {
            try fixture.transaction.signInputInPlace(
                at: 0,
                spending: fixture.outputBeingSpent,
                privateKey: fixture.invalidPrivateKey,
                signatureFormat: .schnorr,
                unlocker: .p2pkh_CheckSig(hashType: hashType),
                spentOutputs: shapeCase.spentOutputs
            )
        }
    }

    @Test(
        "scoped signing-key signing rejects spent-output shape",
        arguments: RawPrivateKeySigningSpentOutputShapeCase.allCases
    )
    func scopedSigningKeySigningRejectsSpentOutputShape(
        _ shapeCase: RawPrivateKeySigningSpentOutputShapeCase
    ) throws {
        let fixture = makeRawPrivateKeySigningValidationFixture()
        let signingKey = try OpalBase.Key.SigningKey(rawRepresentation: Data(repeating: 0x02, count: 32))
        let hashType = OpalBase.Transaction.HashType.makeAll(includesUnspentTransactionOutputs: true)

        #expect(throws: shapeCase.expectedError) {
            try fixture.transaction.signInputInPlace(
                at: 0,
                spending: fixture.outputBeingSpent,
                signingKey: signingKey,
                signatureFormat: .schnorr,
                unlocker: .p2pkh_CheckSig(hashType: hashType),
                spentOutputs: shapeCase.spentOutputs
            )
        }
    }

    @Test("raw private-key signing rejects unsupported hash type before spent-output shape")
    func rawPrivateKeySigningRejectsUnsupportedHashTypeBeforeSpentOutputShape() throws {
        let fixture = makeRawPrivateKeySigningValidationFixture()
        let hashType = OpalBase.Transaction.HashType.makeAll(
            anyoneCanPay: true,
            includesUnspentTransactionOutputs: true
        )

        #expect(throws: OpalBase.Transaction.Error.unsupportedHashType) {
            try fixture.transaction.signInputInPlace(
                at: 0,
                spending: fixture.outputBeingSpent,
                privateKey: fixture.invalidPrivateKey,
                signatureFormat: .schnorr,
                unlocker: .p2pkh_CheckSig(hashType: hashType),
                spentOutputs: nil
            )
        }
    }

    @Test("build produces signatures verifiable through cached verification keys")
    func buildProducesSignaturesVerifiableThroughCachedVerificationKeys() throws {
        let components = try makeTransactionBuilderComponents()
        let unspent = try #require(components.privateKeys.keys.first)
        let hashType = OpalBase.Transaction.HashType.makeAll(anyoneCanPay: false)
        let transaction = try OpalBase.Transaction.build(
            utxoPrivateKeyPairs: components.privateKeys,
            recipientOutputs: components.recipientOutputs,
            changeOutput: components.changeOutput,
            outputOrderingStrategy: .privacyRandomized,
            signatureFormat: .schnorr,
            feePerByte: 0,
            privacyOutputShuffle: { $0 }
        )

        let firstInput = try #require(transaction.inputs.first)
        let decodedUnlockingScript = try decodeP2PKHUnlockingScript(firstInput.unlockingScript)
        let signatureWithHashType = decodedUnlockingScript.signatureWithHashType
        let publicKeyData = decodedUnlockingScript.publicKey
        let signature = try #require(signatureWithHashType.dropLast().isEmpty ? nil : Data(signatureWithHashType.dropLast()))
        let encodedHashType = try #require(signatureWithHashType.last)

        #expect(encodedHashType == UInt8(truncatingIfNeeded: hashType.value))
        #expect(signature.count == 64)

        let outputBeingSpent = OpalBase.Transaction.Output(
            value: unspent.value,
            lockingScript: unspent.lockingScript,
            tokenData: unspent.tokenData
        )
        let preimage = try transaction.generatePreimage(
            for: 0,
            hashType: hashType,
            outputBeingSpent: outputBeingSpent
        )
        let messageDigest = try OpalCrypto.Signature.Digest(rawRepresentation: OpalCrypto.Hashing.hash256(preimage))
        let publicKey = try OpalCrypto.Secp256k1.PublicKey(rawRepresentation: publicKeyData)
        let verificationKey = OpalCrypto.Signature.VerificationKey(publicKey: publicKey)
        let schnorrSignature = try OpalCrypto.Signature.Schnorr(rawRepresentation: signature)

        let isValidThroughCachedKey = try schnorrSignature.verify(
            digest: messageDigest,
            verificationKey: verificationKey
        )
        let isValidThroughPublicKey = try schnorrSignature.verify(
            digest: messageDigest,
            publicKey: publicKey
        )

        #expect(isValidThroughCachedKey)
        #expect(isValidThroughPublicKey)
    }

    @Test("SIGHASH_SINGLE without matching output signs the fixed consensus digest")
    func sighashSingleWithoutMatchingOutputSignsFixedConsensusDigest() throws {
        let privateKey = Data(repeating: 0x02, count: 32)
        let publicKey = try OpalCrypto.Secp256k1.derivePublicKey(
            from: OpalCrypto.Secp256k1.PrivateKey(rawRepresentation: privateKey)
        )
        let fixture = makeSighashSingleFixedDigestFixture()
        let hashType = OpalBase.Transaction.HashType.makeSingle()
        let signed = try fixture.transaction.signInputInPlace(
            at: fixture.signingInputIndex,
            spending: fixture.outputBeingSpent,
            privateKey: privateKey,
            signatureFormat: OpalBase.Transaction.SignatureFormat.schnorr,
            unlocker: OpalBase.Transaction.Unlocker.p2pkh_CheckSig(hashType: hashType)
        )
        let decodedUnlockingScript = try decodeP2PKHUnlockingScript(
            signed.inputs[fixture.signingInputIndex].unlockingScript
        )
        let signatureWithHashType = decodedUnlockingScript.signatureWithHashType
        let signature = try #require(signatureWithHashType.dropLast().isEmpty ? nil : Data(signatureWithHashType.dropLast()))
        var fixedDigest = Data(repeating: 0x00, count: 32)
        fixedDigest[0] = 0x01

        let isValid = try OpalCrypto.Signature.Schnorr(rawRepresentation: signature).verify(
            digest: OpalCrypto.Signature.Digest(rawRepresentation: fixedDigest),
            publicKey: publicKey
        )

        #expect(signatureWithHashType.last == UInt8(truncatingIfNeeded: hashType.value))
        #expect(isValid)
    }

    @Test("scoped signing-key rejects missing UTXO coverage before SIGHASH_SINGLE fixed digest")
    func scopedSigningKeyRejectsMissingUTXOCoverageBeforeSighashSingleFixedDigest() throws {
        let signingKey = try OpalBase.Key.SigningKey(rawRepresentation: Data(repeating: 0x02, count: 32))
        let fixture = makeSighashSingleFixedDigestFixture()
        let hashType = OpalBase.Transaction.HashType.makeSingle(
            includesUnspentTransactionOutputs: true
        )

        #expect(throws: OpalBase.Transaction.Error.missingUnspentTransactionOutputs) {
            _ = try fixture.transaction.signInputInPlace(
                at: fixture.signingInputIndex,
                spending: fixture.outputBeingSpent,
                signingKey: signingKey,
                signatureFormat: .schnorr,
                unlocker: .p2pkh_CheckSig(hashType: hashType)
            )
        }
    }

    @Test("build applies canonical BIP-69 output ordering when requested")
    func buildAppliesCanonicalOutputOrdering() throws {
        let privateKey = Data(repeating: 0x02, count: 32)
        let lockingScript = Data([
            ScriptOperationCode._DUP.rawValue,
            ScriptOperationCode._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x01, count: 20) + [
            ScriptOperationCode._EQUALVERIFY.rawValue,
            ScriptOperationCode._CHECKSIG.rawValue
        ])

        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x00, count: 32))
        let unspent = OpalBase.Transaction.Output.Unspent(
            value: 10_000,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )

        let privateKeys: [OpalBase.Transaction.Output.Unspent: Data] = [unspent: privateKey]

        let recipientOutputs = [
            OpalBase.Transaction.Output(value: 6_000, lockingScript: Data([0x51])),
            OpalBase.Transaction.Output(value: 1_000, lockingScript: Data([0x52]))
        ]

        let changeScript = Data([
            ScriptOperationCode._DUP.rawValue,
            ScriptOperationCode._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x02, count: 20) + [
            ScriptOperationCode._EQUALVERIFY.rawValue,
            ScriptOperationCode._CHECKSIG.rawValue
        ])
        let changeOutput = OpalBase.Transaction.Output(value: 3_000, lockingScript: changeScript)

        let transaction = try OpalBase.Transaction.build(
            utxoPrivateKeyPairs: privateKeys,
            recipientOutputs: recipientOutputs,
            changeOutput: changeOutput,
            outputOrderingStrategy: .canonicalBIP69,
            signatureFormat: .ecdsa(.der),
            feePerByte: 0
        )

        try #require(transaction.outputs.count == 3)
        #expect(transaction.outputs.map(\.value) == [1_000, 3_000, 6_000])
        #expect(transaction.outputs[1].lockingScript == changeScript)
    }

    @Test("build applies privacy output shuffler to recipients and change outputs")
    func buildAppliesPrivacyOutputShufflerToRecipientsAndChangeOutputs() throws {
        let components = try makeTransactionBuilderComponents()
        let transaction = try OpalBase.Transaction.build(
            utxoPrivateKeyPairs: components.privateKeys,
            recipientOutputs: components.recipientOutputs,
            changeOutput: components.changeOutput,
            outputOrderingStrategy: .privacyRandomized,
            signatureFormat: .schnorr,
            feePerByte: 0,
            privacyOutputShuffle: { outputs in
                Array(outputs.reversed())
            }
        )

        #expect(transaction.outputs.count == 3)
        #expect(transaction.outputs.map(\.value) == [3_000, 1_000, 6_000])
        let firstOutput = try #require(transaction.outputs.first)
        let lastOutput = try #require(transaction.outputs.last)
        #expect(firstOutput.lockingScript == components.changeOutput.lockingScript)
        #expect(lastOutput.lockingScript != components.changeOutput.lockingScript)
    }

    @Test("build rejects privacy shufflers that drop outputs")
    func buildRejectsPrivacyShufflersThatDropOutputs() throws {
        let components = try makeTransactionBuilderComponents()

        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            _ = try OpalBase.Transaction.build(
                utxoPrivateKeyPairs: components.privateKeys,
                recipientOutputs: components.recipientOutputs,
                changeOutput: components.changeOutput,
                outputOrderingStrategy: .privacyRandomized,
                signatureFormat: .schnorr,
                feePerByte: 0,
                privacyOutputShuffle: { Array($0.dropLast()) }
            )
        }
    }

    @Test("build corrects fee to match the signed transaction size", arguments: [UInt64(1), UInt64(3)])
    func buildCorrectsFeeToSignedTransactionSize(feePerByte: UInt64) throws {
        let components = try makeTransactionBuilderComponents()
        let transaction = try OpalBase.Transaction.build(
            utxoPrivateKeyPairs: components.privateKeys,
            recipientOutputs: components.recipientOutputs,
            changeOutput: components.changeOutput,
            outputOrderingStrategy: .privacyRandomized,
            signatureFormat: .ecdsa(.der),
            feePerByte: feePerByte
        )

        let requiredFee = try transaction.calculateRequiredFee(feePerByte: feePerByte)
        let outputTotal = transaction.outputs.map(\.value).reduce(0, +)
        let feePaid = components.inputTotal - outputTotal

        let overpaymentTolerance = max(1, feePerByte * 2)
        try #require(feePaid >= requiredFee)
        let feeOverpayment = feePaid - requiredFee
        #expect(feeOverpayment <= overpaymentTolerance)
    }

    @Test("build reuses privacy output order during fee correction")
    func buildReusesPrivacyOutputOrderDuringFeeCorrection() throws {
        let components = try makeTransactionBuilderComponents(inputValue: 12_000, changeValue: 5_000)
        var shuffleCallCount = 0

        let transaction = try OpalBase.Transaction.build(
            utxoPrivateKeyPairs: components.privateKeys,
            recipientOutputs: components.recipientOutputs,
            changeOutput: components.changeOutput,
            outputOrderingStrategy: .privacyRandomized,
            signatureFormat: .ecdsa(.der),
            feePerByte: 1,
            privacyOutputShuffle: { outputs in
                defer { shuffleCallCount += 1 }
                guard shuffleCallCount == 0 else { return Array(outputs.reversed()) }
                return outputs
            }
        )

        let requiredFee = try transaction.calculateRequiredFee(feePerByte: 1)
        let outputTotal = transaction.outputs.map(\.value).reduce(0, +)
        let feePaid = components.inputTotal - outputTotal

        #expect(feePaid >= requiredFee)
        #expect(shuffleCallCount == 1)
    }

    @Test("build preserves duplicate recipient privacy order during fee correction")
    func buildPreservesDuplicateRecipientPrivacyOrderDuringFeeCorrection() throws {
        let components = try makeTransactionBuilderComponents(inputValue: 13_000, changeValue: 6_000)
        let sharedLockingScript = Data([0x51])
        let recipientOutputs = [
            OpalBase.Transaction.Output(value: 6_000, lockingScript: sharedLockingScript),
            OpalBase.Transaction.Output(value: 1_000, lockingScript: sharedLockingScript)
        ]

        let transaction = try OpalBase.Transaction.build(
            utxoPrivateKeyPairs: components.privateKeys,
            recipientOutputs: recipientOutputs,
            changeOutput: components.changeOutput,
            outputOrderingStrategy: .privacyRandomized,
            signatureFormat: .ecdsa(.der),
            feePerByte: 1,
            privacyOutputShuffle: { Array($0.reversed()) }
        )

        let duplicateRecipientValues = transaction.outputs
            .filter { $0.lockingScript == sharedLockingScript }
            .map(\.value)
        #expect(duplicateRecipientValues == [1_000, 6_000])
    }

    @Test(
        "build correction respects output ordering strategies",
        arguments: [
            OpalBase.Transaction.OutputOrderingStrategy.privacyRandomized,
            .canonicalBIP69
        ]
    )
    func buildCorrectionRespectsOutputOrderingStrategies(strategy: OpalBase.Transaction.OutputOrderingStrategy) throws {
        let components = try makeTransactionBuilderComponents()
        let transaction = try OpalBase.Transaction.build(
            utxoPrivateKeyPairs: components.privateKeys,
            recipientOutputs: components.recipientOutputs,
            changeOutput: components.changeOutput,
            outputOrderingStrategy: strategy,
            signatureFormat: .ecdsa(.der),
            feePerByte: 2
        )

        let requiredFee = try transaction.calculateRequiredFee(feePerByte: 2)
        let outputTotal = transaction.outputs.map(\.value).reduce(0, +)
        let feePaid = components.inputTotal - outputTotal

        #expect(feePaid >= requiredFee)
        if feePaid >= requiredFee {
            let feeOverpayment = feePaid - requiredFee
            #expect(feeOverpayment <= 2)
        }
    }

    @Test("build rejects non-converging dust-boundary fee correction")
    func buildRejectsNonConvergingDustBoundaryFeeCorrection() throws {
        let privateKey = Data(repeating: 0x02, count: 32)
        let lockingScript = Data([
            ScriptOperationCode._DUP.rawValue,
            ScriptOperationCode._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x01, count: 20) + [
            ScriptOperationCode._EQUALVERIFY.rawValue,
            ScriptOperationCode._CHECKSIG.rawValue
        ])
        let unspent = OpalBase.Transaction.Output.Unspent(
            value: 1_720,
            lockingScript: lockingScript,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x00, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let privateKeys: [OpalBase.Transaction.Output.Unspent: Data] = [unspent: privateKey]
        let recipientOutputs = [OpalBase.Transaction.Output(value: 1_000, lockingScript: Data([0x51]))]
        let changeOutput = OpalBase.Transaction.Output(value: 720, lockingScript: lockingScript)

        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            _ = try OpalBase.Transaction.build(
                utxoPrivateKeyPairs: privateKeys,
                recipientOutputs: recipientOutputs,
                changeOutput: changeOutput,
                outputOrderingStrategy: .privacyRandomized,
                signatureFormat: .schnorr,
                feePerByte: 1,
                shouldAllowDustDonation: true,
                privacyOutputShuffle: { $0 }
            )
        }
    }

    @Test("build rejects overstated change pool with insufficient funds")
    func buildRejectsOverstatedChangePool() throws {
        let components = try makeTransactionBuilderComponents()
        let overstatedChangeOutput = OpalBase.Transaction.Output(
            value: components.changeOutput.value + 5_000,
            lockingScript: components.changeOutput.lockingScript
        )

        let error = try Self.captureBuildTransactionError {
            _ = try OpalBase.Transaction.build(
                utxoPrivateKeyPairs: components.privateKeys,
                recipientOutputs: components.recipientOutputs,
                changeOutput: overstatedChangeOutput,
                outputOrderingStrategy: .canonicalBIP69,
                signatureFormat: .ecdsa(.der),
                feePerByte: 1
            )
        }

        guard case .insufficientFunds(let required) = error else {
            throw BuildTransactionErrorCaptureFailure.unexpected(error)
        }
        #expect(required > 0)
    }

    @Test("build throws when input totals overflow UInt64 during fee correction")
    func buildThrowsWhenInputTotalsOverflowUInt64DuringFeeCorrection() throws {
        let lockingScript = Data([
            ScriptOperationCode._DUP.rawValue,
            ScriptOperationCode._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x01, count: 20) + [
            ScriptOperationCode._EQUALVERIFY.rawValue,
            ScriptOperationCode._CHECKSIG.rawValue
        ])

        let firstUnspent = OpalBase.Transaction.Output.Unspent(
            value: UInt64.max - 1,
            lockingScript: lockingScript,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x01, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let secondUnspent = OpalBase.Transaction.Output.Unspent(
            value: 10,
            lockingScript: lockingScript,
            previousTransactionHash: OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x02, count: 32)),
            previousTransactionOutputIndex: 1
        )

        let privateKeys: [OpalBase.Transaction.Output.Unspent: Data] = [
            firstUnspent: Data(repeating: 0x02, count: 32),
            secondUnspent: Data(repeating: 0x03, count: 32)
        ]
        let recipientOutputs = [OpalBase.Transaction.Output(value: 1_000, lockingScript: Data([0x51]))]
        let changeOutput = OpalBase.Transaction.Output(value: 500, lockingScript: Data([0x52]))

        #expect(throws: OpalBase.Transaction.Error.cannotCreateTransaction) {
            _ = try OpalBase.Transaction.build(
                utxoPrivateKeyPairs: privateKeys,
                recipientOutputs: recipientOutputs,
                changeOutput: changeOutput,
                outputOrderingStrategy: .privacyRandomized,
                signatureFormat: .schnorr,
                feePerByte: 0,
                privacyOutputShuffle: { $0 }
            )
        }
    }
}

extension TransactionUnspentTransactionOutputValidator {
    enum UnselectedUnlockerBoundaryCase: CaseIterable, CustomStringConvertible, Sendable {
        case signedBuild
        case unsignedEnvelope

        var description: String {
            switch self {
            case .signedBuild:
                "signed build"
            case .unsignedEnvelope:
                "unsigned envelope"
            }
        }
    }

    private enum BuildTransactionErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
    }

    enum RawPrivateKeySigningSpentOutputShapeCase: CaseIterable, CustomStringConvertible, Sendable {
        case missing
        case countMismatch

        var description: String {
            switch self {
            case .missing:
                "missing spent outputs"
            case .countMismatch:
                "spent output count mismatch"
            }
        }

        var spentOutputs: [OpalBase.Transaction.Output]? {
            switch self {
            case .missing:
                nil
            case .countMismatch:
                []
            }
        }

        var expectedError: OpalBase.Transaction.Error {
            switch self {
            case .missing:
                .missingUnspentTransactionOutputs
            case .countMismatch:
                .unspentTransactionOutputsCountMismatch(expected: 1, actual: 0)
            }
        }
    }

    struct SigningTemplateMismatchCase: CaseIterable, CustomStringConvertible, Sendable {
        static let allCases: [SigningTemplateMismatchCase] = SigningTemplateSignerCase.allCases.flatMap { signer in
            SigningTemplateMutationCase.allCases.map { mutation in
                SigningTemplateMismatchCase(signer: signer, mutation: mutation)
            }
        }

        let signer: SigningTemplateSignerCase
        let mutation: SigningTemplateMutationCase

        var description: String {
            "\(signer.description), \(mutation.description)"
        }

        func sign(
            transaction: OpalBase.Transaction,
            outputBeingSpent: OpalBase.Transaction.Output,
            invalidPrivateKey: Data,
            using mismatchedTemplate: OpalBase.Transaction
        ) throws {
            try signer.sign(
                transaction: transaction,
                outputBeingSpent: outputBeingSpent,
                invalidPrivateKey: invalidPrivateKey,
                using: mismatchedTemplate
            )
        }

        func makeMismatchedTemplate(
            from transaction: OpalBase.Transaction
        ) -> OpalBase.Transaction {
            mutation.makeMismatchedTemplate(from: transaction)
        }
    }

    enum SigningTemplateSignerCase: CaseIterable, CustomStringConvertible, Sendable {
        case rawPrivateKey
        case scopedSigningKey

        var description: String {
            switch self {
            case .rawPrivateKey:
                "raw private key"
            case .scopedSigningKey:
                "scoped signing key"
            }
        }

        func sign(
            transaction: OpalBase.Transaction,
            outputBeingSpent: OpalBase.Transaction.Output,
            invalidPrivateKey: Data,
            using mismatchedTemplate: OpalBase.Transaction
        ) throws {
            switch self {
            case .rawPrivateKey:
                _ = try transaction.signInputInPlace(
                    at: 0,
                    spending: outputBeingSpent,
                    privateKey: invalidPrivateKey,
                    signatureFormat: .schnorr,
                    unlocker: .p2pkh_CheckSig(),
                    using: mismatchedTemplate
                )
            case .scopedSigningKey:
                _ = try transaction.signInputInPlace(
                    at: 0,
                    spending: outputBeingSpent,
                    signingKey: OpalBase.Key.SigningKey(rawRepresentation: Data(repeating: 0x02, count: 32)),
                    signatureFormat: .schnorr,
                    unlocker: .p2pkh_CheckSig(),
                    using: mismatchedTemplate
                )
            }
        }
    }

    enum SigningTemplateMutationCase: CaseIterable, CustomStringConvertible, Sendable {
        case currentInputOutpoint
        case extraInput
        case version
        case output
        case lockTime

        var description: String {
            switch self {
            case .currentInputOutpoint:
                "current input outpoint"
            case .extraInput:
                "extra input"
            case .version:
                "version"
            case .output:
                "output"
            case .lockTime:
                "lock time"
            }
        }

        func makeMismatchedTemplate(
            from transaction: OpalBase.Transaction
        ) -> OpalBase.Transaction {
            switch self {
            case .currentInputOutpoint:
                OpalBase.Transaction(
                    version: transaction.version,
                    inputs: [
                        .init(
                            previousTransactionHash: .init(naturalOrder: Data(repeating: 0x02, count: 32)),
                            previousTransactionOutputIndex: transaction.inputs[0].previousTransactionOutputIndex,
                            unlockingScript: transaction.inputs[0].unlockingScript,
                            sequence: transaction.inputs[0].sequence
                        ),
                    ],
                    outputs: transaction.outputs,
                    lockTime: transaction.lockTime
                )
            case .extraInput:
                OpalBase.Transaction(
                    version: transaction.version,
                    inputs: transaction.inputs + [
                        .init(
                            previousTransactionHash: .init(naturalOrder: Data(repeating: 0x03, count: 32)),
                            previousTransactionOutputIndex: 1,
                            unlockingScript: Data()
                        ),
                    ],
                    outputs: transaction.outputs,
                    lockTime: transaction.lockTime
                )
            case .version:
                OpalBase.Transaction(
                    version: transaction.version + 1,
                    inputs: transaction.inputs,
                    outputs: transaction.outputs,
                    lockTime: transaction.lockTime
                )
            case .output:
                OpalBase.Transaction(
                    version: transaction.version,
                    inputs: transaction.inputs,
                    outputs: [
                        .init(
                            value: transaction.outputs[0].value - 1,
                            lockingScript: transaction.outputs[0].lockingScript,
                            tokenData: transaction.outputs[0].tokenData
                        ),
                    ],
                    lockTime: transaction.lockTime
                )
            case .lockTime:
                OpalBase.Transaction(
                    version: transaction.version,
                    inputs: transaction.inputs,
                    outputs: transaction.outputs,
                    lockTime: transaction.lockTime + 1
                )
            }
        }
    }

    private static func captureBuildTransactionError(
        _ work: () throws -> Void
    ) throws -> OpalBase.Transaction.Error {
        do {
            try work()
            throw BuildTransactionErrorCaptureFailure.didNotThrow
        } catch let error as OpalBase.Transaction.Error {
            return error
        } catch let error as BuildTransactionErrorCaptureFailure {
            throw error
        } catch {
            throw BuildTransactionErrorCaptureFailure.unexpected(error)
        }
    }

    private func makeRawPrivateKeySigningValidationFixture() -> (
        invalidPrivateKey: Data,
        outputBeingSpent: OpalBase.Transaction.Output,
        transaction: OpalBase.Transaction
    ) {
        let outputBeingSpent = OpalBase.Transaction.Output(
            value: 1_000,
            lockingScript: Data([0x51])
        )
        let transaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: .init(naturalOrder: Data(repeating: 0x01, count: 32)),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data()
                )
            ],
            outputs: [
                .init(value: 900, lockingScript: Data([0x51]))
            ],
            lockTime: 0
        )

        return (
            invalidPrivateKey: Data(repeating: 0x01, count: 31),
            outputBeingSpent: outputBeingSpent,
            transaction: transaction
        )
    }

    private func makeSighashSingleFixedDigestFixture() -> (
        signingInputIndex: Int,
        outputBeingSpent: OpalBase.Transaction.Output,
        transaction: OpalBase.Transaction
    ) {
        let lockingScript = Data([
            ScriptOperationCode._DUP.rawValue,
            ScriptOperationCode._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x01, count: 20) + [
            ScriptOperationCode._EQUALVERIFY.rawValue,
            ScriptOperationCode._CHECKSIG.rawValue
        ])
        let outputBeingSpent = OpalBase.Transaction.Output(value: 10_000, lockingScript: lockingScript)
        let transaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: .init(naturalOrder: Data(repeating: 0x01, count: 32)),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data()
                ),
                .init(
                    previousTransactionHash: .init(naturalOrder: Data(repeating: 0x02, count: 32)),
                    previousTransactionOutputIndex: 1,
                    unlockingScript: Data()
                )
            ],
            outputs: [
                .init(value: 1_000, lockingScript: Data([0x51]))
            ],
            lockTime: 0
        )

        return (
            signingInputIndex: 1,
            outputBeingSpent: outputBeingSpent,
            transaction: transaction
        )
    }

    private func decodeP2PKHUnlockingScript(
        _ unlockingScript: Data
    ) throws -> (signatureWithHashType: Data, publicKey: Data) {
        let bytes = Array(unlockingScript)
        var offset = 0
        let signatureWithHashType = try Data(readPushedElement(from: bytes, offset: &offset))
        let publicKey = try Data(readPushedElement(from: bytes, offset: &offset))

        guard offset == bytes.count else {
            throw P2PKHUnlockingScriptDecodingError.trailingBytes
        }

        return (signatureWithHashType, publicKey)
    }

    private func readPushedElement(
        from bytes: [UInt8],
        offset: inout Int
    ) throws -> [UInt8] {
        guard offset < bytes.count else {
            throw P2PKHUnlockingScriptDecodingError.truncated
        }

        let opcode = bytes[offset]
        offset += 1

        let count: Int
        switch opcode {
        case 0 ... 75:
            count = Int(opcode)
        case ScriptOperationCode._PUSHDATA1.rawValue:
            guard offset < bytes.count else {
                throw P2PKHUnlockingScriptDecodingError.truncated
            }
            count = Int(bytes[offset])
            offset += 1
        case ScriptOperationCode._PUSHDATA2.rawValue:
            guard offset + 1 < bytes.count else {
                throw P2PKHUnlockingScriptDecodingError.truncated
            }
            count = Int(UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8))
            offset += 2
        case ScriptOperationCode._PUSHDATA4.rawValue:
            guard offset + 3 < bytes.count else {
                throw P2PKHUnlockingScriptDecodingError.truncated
            }
            count = Int(
                UInt32(bytes[offset]) |
                    (UInt32(bytes[offset + 1]) << 8) |
                    (UInt32(bytes[offset + 2]) << 16) |
                    (UInt32(bytes[offset + 3]) << 24)
            )
            offset += 4
        default:
            throw P2PKHUnlockingScriptDecodingError.unsupportedPushOpcode(opcode)
        }

        guard offset + count <= bytes.count else {
            throw P2PKHUnlockingScriptDecodingError.truncated
        }

        let element = Array(bytes[offset ..< offset + count])
        offset += count
        return element
    }
}
