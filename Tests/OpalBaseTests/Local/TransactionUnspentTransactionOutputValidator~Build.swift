// TransactionUnspentTransactionOutputValidator~Build.swift

import Foundation
import Testing
@testable import OpalBase

extension TransactionUnspentTransactionOutputValidator {
    @Test("build applies canonical BIP-69 output ordering when requested")
    func buildAppliesCanonicalOutputOrdering() throws {
        let privateKey = try OpalBase.PrivateKey(data: Data(repeating: 0x02, count: 32))
        let lockingScript = Data([
            ScriptOperationCodeModel._DUP.rawValue,
            ScriptOperationCodeModel._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x01, count: 20) + [
            ScriptOperationCodeModel._EQUALVERIFY.rawValue,
            ScriptOperationCodeModel._CHECKSIG.rawValue
        ])
        
        let previousTransactionHash = OpalBase.Transaction.HashModel(naturalOrder: Data(repeating: 0x00, count: 32))
        let unspent = OpalBase.Transaction.OutputModel.Unspent(
            value: 10_000,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let privateKeys: [OpalBase.Transaction.OutputModel.Unspent: OpalBase.PrivateKey] = [unspent: privateKey]
        
        let recipientOutputs = [
            OpalBase.Transaction.OutputModel(value: 6_000, lockingScript: Data([0x51])),
            OpalBase.Transaction.OutputModel(value: 1_000, lockingScript: Data([0x52]))
        ]
        
        let changeScript = Data([
            ScriptOperationCodeModel._DUP.rawValue,
            ScriptOperationCodeModel._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x02, count: 20) + [
            ScriptOperationCodeModel._EQUALVERIFY.rawValue,
            ScriptOperationCodeModel._CHECKSIG.rawValue
        ])
        let changeOutput = OpalBase.Transaction.OutputModel(value: 3_000, lockingScript: changeScript)
        
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
        let outputOrderingStrategies: [OpalBase.Transaction.OutputOrderingStrategyModel] = [.privacyRandomized, .canonicalBIP69]
        
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
}
