import Foundation
import Testing
@testable import OpalBase

@Suite("TransactionModel UTXOModel", .tags(.unit, .transaction))
struct TransactionUnspentTransactionOutputValidator {
    @Test("build applies canonical BIP-69 output ordering when requested")
    func buildAppliesCanonicalOutputOrdering() throws {
        let privateKey = try PrivateKeyModel(data: Data(repeating: 0x02, count: 32))
        let lockingScript = Data([
            ScriptOperationCodeModel._DUP.rawValue,
            ScriptOperationCodeModel._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x01, count: 20) + [
            ScriptOperationCodeModel._EQUALVERIFY.rawValue,
            ScriptOperationCodeModel._CHECKSIG.rawValue
        ])
        
        let previousTransactionHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 0x00, count: 32))
        let unspent = TransactionModel.OutputModel.UnspentModel(
            value: 10_000,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel] = [unspent: privateKey]
        
        let recipientOutputs = [
            TransactionModel.OutputModel(value: 6_000, lockingScript: Data([0x51])),
            TransactionModel.OutputModel(value: 1_000, lockingScript: Data([0x52]))
        ]
        
        let changeScript = Data([
            ScriptOperationCodeModel._DUP.rawValue,
            ScriptOperationCodeModel._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x02, count: 20) + [
            ScriptOperationCodeModel._EQUALVERIFY.rawValue,
            ScriptOperationCodeModel._CHECKSIG.rawValue
        ])
        let changeOutput = TransactionModel.OutputModel(value: 3_000, lockingScript: changeScript)
        
        let transaction = try TransactionModel.build(
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
    
    @Test("build randomizes recipient ordering when privacyRandomized is requested")
    func buildRandomizesRecipientOrderingWhenPrivacyRandomized() throws {
        let components = try makeTransactionBuilderComponents()
        var observedRecipientOrderings = Set<[UInt64]>()
        
        for _ in 0..<32 {
            let transaction = try TransactionModel.build(
                utxoPrivateKeyPairs: components.privateKeys,
                recipientOutputs: components.recipientOutputs,
                changeOutput: components.changeOutput,
                outputOrderingStrategy: .privacyRandomized,
                signatureFormat: .schnorr,
                feePerByte: 0
            )
            
            let recipientOrder = transaction.outputs
                .filter { $0.lockingScript != components.changeOutput.lockingScript }
                .map(\.value)
            observedRecipientOrderings.insert(recipientOrder)
            if observedRecipientOrderings.count > 1 { break }
        }
        
        #expect(observedRecipientOrderings.count > 1)
    }
    
    @Test("build corrects fee to match the signed transaction size")
    func buildCorrectsFeeToSignedTransactionSize() throws {
        let components = try makeTransactionBuilderComponents()
        let feePerByteValues: [UInt64] = [1, 3]
        
        for feePerByte in feePerByteValues {
            let transaction = try TransactionModel.build(
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
        let outputOrderingStrategies: [TransactionModel.OutputOrderingStrategyModel] = [.privacyRandomized, .canonicalBIP69]
        
        for strategy in outputOrderingStrategies {
            let transaction = try TransactionModel.build(
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
    
    @Test("computeOutputsForTargetFee handles dust donation policy")
    func computeOutputsForTargetFeeHandlesDustDonationPolicy() throws {
        let recipientOutputs = [TransactionModel.OutputModel(value: 1_000, lockingScript: Data([0x51]))]
        let changeOutput = TransactionModel.OutputModel(value: 900, lockingScript: Data([0x52]))
        let targetFee = UInt64(850)
        
        let donationOutputs = try TransactionModel.computeOutputsForTargetFee(recipientOutputs: recipientOutputs,
                                                                         changeOutputTemplate: changeOutput,
                                                                         outputOrderingStrategy: .privacyRandomized,
                                                                         targetFee: targetFee,
                                                                         shouldAllowDustDonation: true)
        
        #expect(donationOutputs.count == recipientOutputs.count)
        
        #expect(throws: TransactionModel.Error.outputValueIsLessThanTheDustLimit) {
            _ = try TransactionModel.computeOutputsForTargetFee(recipientOutputs: recipientOutputs,
                                                           changeOutputTemplate: changeOutput,
                                                           outputOrderingStrategy: .privacyRandomized,
                                                           targetFee: targetFee,
                                                           shouldAllowDustDonation: false)
        }
    }
    
    private func makeTransactionBuilderComponents() throws -> (privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel],
                                                               recipientOutputs: [TransactionModel.OutputModel],
                                                               changeOutput: TransactionModel.OutputModel,
                                                               inputTotal: UInt64) {
        let privateKey = try PrivateKeyModel(data: Data(repeating: 0x02, count: 32))
        let lockingScript = Data([
            ScriptOperationCodeModel._DUP.rawValue,
            ScriptOperationCodeModel._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x01, count: 20) + [
            ScriptOperationCodeModel._EQUALVERIFY.rawValue,
            ScriptOperationCodeModel._CHECKSIG.rawValue
        ])
        
        let previousTransactionHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 0x00, count: 32))
        let unspent = TransactionModel.OutputModel.UnspentModel(
            value: 10_000,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel] = [unspent: privateKey]
        
        let recipientOutputs = [
            TransactionModel.OutputModel(value: 6_000, lockingScript: Data([0x51])),
            TransactionModel.OutputModel(value: 1_000, lockingScript: Data([0x52]))
        ]
        
        let changeScript = Data([
            ScriptOperationCodeModel._DUP.rawValue,
            ScriptOperationCodeModel._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x02, count: 20) + [
            ScriptOperationCodeModel._EQUALVERIFY.rawValue,
            ScriptOperationCodeModel._CHECKSIG.rawValue
        ])
        let changeOutput = TransactionModel.OutputModel(value: 3_000, lockingScript: changeScript)
        
        return (privateKeys: privateKeys,
                recipientOutputs: recipientOutputs,
                changeOutput: changeOutput,
                inputTotal: unspent.value)
    }
}
