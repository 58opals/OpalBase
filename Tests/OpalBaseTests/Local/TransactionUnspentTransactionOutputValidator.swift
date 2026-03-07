// TransactionUnspentTransactionOutputValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Transaction UTXO", .tags(.unit, .transaction))
struct TransactionUnspentTransactionOutputValidator {
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
    
    @Test("build preserves token metadata on change outputs")
    func buildPreservesTokenMetadataOnChangeOutputs() throws {
        let components = try makeTransactionBuilderComponents()
        let tokenData = try makeTokenData(fillByte: 0xA5, amount: 21)
        let tokenizedChangeOutput = OpalBase.Transaction.OutputModel(
            value: components.changeOutput.value,
            lockingScript: components.changeOutput.lockingScript,
            tokenData: tokenData
        )
        
        let transaction = try OpalBase.Transaction.build(
            utxoPrivateKeyPairs: components.privateKeys,
            recipientOutputs: components.recipientOutputs,
            changeOutput: tokenizedChangeOutput,
            outputOrderingStrategy: .privacyRandomized,
            signatureFormat: .schnorr,
            feePerByte: 0,
            privacyOutputShuffle: { $0 }
        )
        
        let resolvedChangeOutput = try #require(transaction.outputs.first { output in
            output.lockingScript == tokenizedChangeOutput.lockingScript && output.value == tokenizedChangeOutput.value
        })
        #expect(resolvedChangeOutput.tokenData == tokenData)
    }
    
    @Test("computeOutputsForTargetFee handles dust donation policy")
    func computeOutputsForTargetFeeHandlesDustDonationPolicy() throws {
        let recipientOutputs = [OpalBase.Transaction.OutputModel(value: 1_000, lockingScript: Data([0x51]))]
        let changeOutput = OpalBase.Transaction.OutputModel(value: 900, lockingScript: Data([0x52]))
        let targetFee = UInt64(850)
        
        let donationOutputs = try OpalBase.Transaction.computeOutputsForTargetFee(recipientOutputs: recipientOutputs,
                                                                         changeOutputTemplate: changeOutput,
                                                                         outputOrderingStrategy: .privacyRandomized,
                                                                         targetFee: targetFee,
                                                                         shouldAllowDustDonation: true)
        
        #expect(donationOutputs.count == recipientOutputs.count)
        
        #expect(throws: OpalBase.Transaction.Error.outputValueIsLessThanTheDustLimit) {
            _ = try OpalBase.Transaction.computeOutputsForTargetFee(recipientOutputs: recipientOutputs,
                                                           changeOutputTemplate: changeOutput,
                                                           outputOrderingStrategy: .privacyRandomized,
                                                           targetFee: targetFee,
                                                           shouldAllowDustDonation: false)
        }
    }
    
    @Test("computeOutputsForTargetFee applies privacy output shuffler to change output")
    func computeOutputsForTargetFeeAppliesPrivacyOutputShuffler() throws {
        let recipientA = OpalBase.Transaction.OutputModel(value: 6_000, lockingScript: Data([0x51]))
        let recipientB = OpalBase.Transaction.OutputModel(value: 1_000, lockingScript: Data([0x52]))
        let changeOutput = OpalBase.Transaction.OutputModel(value: 3_000, lockingScript: Data([0x53]))
        
        let outputs = try OpalBase.Transaction.computeOutputsForTargetFee(
            recipientOutputs: [recipientA, recipientB],
            changeOutputTemplate: changeOutput,
            outputOrderingStrategy: .privacyRandomized,
            targetFee: 0,
            shouldAllowDustDonation: false,
            privacyOutputShuffle: { values in Array(values.reversed()) }
        )
        
        #expect(outputs.map(\.value) == [3_000, 1_000, 6_000])
        #expect(outputs.first?.lockingScript == changeOutput.lockingScript)
    }
    
    @Test("computeOutputsForTargetFee preserves token metadata on change outputs")
    func computeOutputsForTargetFeePreservesTokenMetadataOnChangeOutputs() throws {
        let recipientOutput = OpalBase.Transaction.OutputModel(value: 1_000, lockingScript: Data([0x51]))
        let tokenData = try makeTokenData(fillByte: 0x5A, amount: 7)
        let changeOutput = OpalBase.Transaction.OutputModel(
            value: 3_000,
            lockingScript: Data([0x53]),
            tokenData: tokenData
        )
        
        let outputs = try OpalBase.Transaction.computeOutputsForTargetFee(
            recipientOutputs: [recipientOutput],
            changeOutputTemplate: changeOutput,
            outputOrderingStrategy: .privacyRandomized,
            targetFee: 0,
            shouldAllowDustDonation: false,
            privacyOutputShuffle: { $0 }
        )
        
        let resolvedChangeOutput = try #require(outputs.first { output in
            output.lockingScript == changeOutput.lockingScript && output.value == changeOutput.value
        })
        #expect(resolvedChangeOutput.tokenData == tokenData)
    }
    
    private func makeTransactionBuilderComponents() throws -> (privateKeys: [OpalBase.Transaction.OutputModel.Unspent: OpalBase.PrivateKey],
                                                               recipientOutputs: [OpalBase.Transaction.OutputModel],
                                                               changeOutput: OpalBase.Transaction.OutputModel,
                                                               inputTotal: UInt64) {
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
        
        return (privateKeys: privateKeys,
                recipientOutputs: recipientOutputs,
                changeOutput: changeOutput,
                inputTotal: unspent.value)
    }
    
    private func makeTokenData(fillByte: UInt8, amount: UInt64) throws -> OpalBase.CashTokens.TokenData {
        let category = try OpalBase.CashTokens.CategoryIDModel(
            transactionOrderData: Data(repeating: fillByte, count: 32)
        )
        return OpalBase.CashTokens.TokenData(category: category, amount: amount, nft: nil)
    }
}

