// TransactionUnspentTransactionOutputValidator~Build.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalBase

extension TransactionUnspentTransactionOutputValidator {
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
        let hashType = OpalBase.Transaction.HashType.makeSingle()
        let signed = try transaction.signInputInPlace(
            at: 1,
            spending: outputBeingSpent,
            privateKey: privateKey,
            signatureFormat: OpalBase.Transaction.SignatureFormat.schnorr,
            unlocker: OpalBase.Transaction.Unlocker.p2pkh_CheckSig(hashType: hashType)
        )
        let decodedUnlockingScript = try decodeP2PKHUnlockingScript(signed.inputs[1].unlockingScript)
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
        
        #expect(transaction.outputs.count == 3)
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
    
    @Test("build corrects fee to match the signed transaction size")
    func buildCorrectsFeeToSignedTransactionSize() throws {
        let components = try makeTransactionBuilderComponents()
        let feePerByteValues: [UInt64] = [1, 3]
        
        for feePerByte in feePerByteValues {
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
            guard feePaid >= requiredFee else {
                Issue.record("Expected feePaid to be >= requiredFee, got feePaid=\(feePaid), requiredFee=\(requiredFee)")
                continue
            }
            let feeOverpayment = feePaid - requiredFee
            #expect(feeOverpayment <= overpaymentTolerance)
        }
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
    
    @Test("build correction respects output ordering strategies")
    func buildCorrectionRespectsOutputOrderingStrategies() throws {
        let components = try makeTransactionBuilderComponents()
        let outputOrderingStrategies: [OpalBase.Transaction.OutputOrderingStrategy] = [.privacyRandomized, .canonicalBIP69]
        
        for strategy in outputOrderingStrategies {
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
    private enum BuildTransactionErrorCaptureFailure: Swift.Error {
        case didNotThrow
        case unexpected(Swift.Error)
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
