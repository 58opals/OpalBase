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
        let publicKey = decodedUnlockingScript.publicKey
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
        let messageDigest = OpalCrypto.Hashing.computeHash256(preimage)
        let verificationKey = try OpalCrypto.Signature.VerificationKey(publicKey: publicKey)

        let isValidThroughCachedKey = try OpalCrypto.Signature.verifySchnorr(
            signature: signature,
            digest: messageDigest,
            verificationKey: verificationKey
        )
        let isValidThroughLegacyPath = try OpalCrypto.Signature.verifySchnorr(
            signature: signature,
            digest: messageDigest,
            publicKey: publicKey
        )

        #expect(isValidThroughCachedKey)
        #expect(isValidThroughLegacyPath)
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
        #expect(transaction.outputs.first?.lockingScript == components.changeOutput.lockingScript)
        #expect(transaction.outputs.last?.lockingScript != components.changeOutput.lockingScript)
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
            
            #expect(feePaid == requiredFee)
        }
    }
    
    @Test("build rejects overstated change pool with insufficient funds")
    func buildRejectsOverstatedChangePool() throws {
        let components = try makeTransactionBuilderComponents()
        let overstatedChangeOutput = OpalBase.Transaction.Output(
            value: components.changeOutput.value + 5_000,
            lockingScript: components.changeOutput.lockingScript
        )
        
        do {
            _ = try OpalBase.Transaction.build(
                utxoPrivateKeyPairs: components.privateKeys,
                recipientOutputs: components.recipientOutputs,
                changeOutput: overstatedChangeOutput,
                outputOrderingStrategy: .canonicalBIP69,
                signatureFormat: .ecdsa(.der),
                feePerByte: 1
            )
            Issue.record("Expected insufficientFunds for overstated change output.")
        } catch let error as OpalBase.Transaction.Error {
            switch error {
            case .insufficientFunds(let required):
                #expect(required > 0)
            default:
                Issue.record("Expected insufficientFunds, got \(error).")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
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

private enum P2PKHUnlockingScriptDecodingError: Error {
    case truncated
    case unsupportedPushOpcode(UInt8)
    case trailingBytes
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
