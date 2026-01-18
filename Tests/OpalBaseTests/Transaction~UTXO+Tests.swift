import Foundation
import Testing
@testable import OpalBase

@Suite("Transaction UTXO", .tags(.unit, .transaction))
struct TransactionUTXOTests {
    @Test("build applies canonical BIP-69 output ordering when requested")
    func testBuildAppliesCanonicalOutputOrdering() throws {
        let privateKey = try PrivateKey(data: Data(repeating: 0x02, count: 32))
        let lockingScript = Data([
            OP._DUP.rawValue,
            OP._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x01, count: 20) + [
            OP._EQUALVERIFY.rawValue,
            OP._CHECKSIG.rawValue
        ])
        
        let previousTransactionHash = Transaction.Hash(naturalOrder: Data(repeating: 0x00, count: 32))
        let unspent = Transaction.Output.Unspent(
            value: 10_000,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let privateKeys: [Transaction.Output.Unspent: PrivateKey] = [unspent: privateKey]
        
        let recipientOutputs = [
            Transaction.Output(value: 6_000, lockingScript: Data([0x51])),
            Transaction.Output(value: 1_000, lockingScript: Data([0x52]))
        ]
        
        let changeScript = Data([
            OP._DUP.rawValue,
            OP._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x02, count: 20) + [
            OP._EQUALVERIFY.rawValue,
            OP._CHECKSIG.rawValue
        ])
        let changeOutput = Transaction.Output(value: 3_000, lockingScript: changeScript)
        
        let transaction = try Transaction.build(
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
    
    @Test("build corrects fee to match the signed transaction size")
    func testBuildCorrectsFeeToSignedTransactionSize() throws {
        let components = try makeTransactionBuilderComponents()
        let feePerByteValues: [UInt64] = [1, 3]
        
        for feePerByte in feePerByteValues {
            let transaction = try Transaction.build(
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
            
            let strictlyEqual = (feePaid == requiredFee)
            let extra1Satoshitolerance = (feePaid == (requiredFee + 1))
            
            #expect(strictlyEqual || extra1Satoshitolerance)
        }
    }
    
    @Test("build correction respects output ordering strategies")
    func testBuildCorrectionRespectsOutputOrderingStrategies() throws {
        let components = try makeTransactionBuilderComponents()
        let outputOrderingStrategies: [Transaction.OutputOrderingStrategy] = [.privacyRandomized, .canonicalBIP69]
        
        for strategy in outputOrderingStrategies {
            let transaction = try Transaction.build(
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
    func testComputeOutputsForTargetFeeHandlesDustDonationPolicy() throws {
        let recipientOutputs = [Transaction.Output(value: 1_000, lockingScript: Data([0x51]))]
        let changeOutput = Transaction.Output(value: 900, lockingScript: Data([0x52]))
        let targetFee = UInt64(850)
        
        let donationOutputs = try Transaction.computeOutputsForTargetFee(recipientOutputs: recipientOutputs,
                                                                         changeOutputTemplate: changeOutput,
                                                                         outputOrderingStrategy: .privacyRandomized,
                                                                         targetFee: targetFee,
                                                                         shouldAllowDustDonation: true)
        
        #expect(donationOutputs.count == recipientOutputs.count)
        
        #expect(throws: Transaction.Error.outputValueIsLessThanTheDustLimit) {
            _ = try Transaction.computeOutputsForTargetFee(recipientOutputs: recipientOutputs,
                                                           changeOutputTemplate: changeOutput,
                                                           outputOrderingStrategy: .privacyRandomized,
                                                           targetFee: targetFee,
                                                           shouldAllowDustDonation: false)
        }
    }
    
    private func makeTransactionBuilderComponents() throws -> (privateKeys: [Transaction.Output.Unspent: PrivateKey],
                                                               recipientOutputs: [Transaction.Output],
                                                               changeOutput: Transaction.Output,
                                                               inputTotal: UInt64) {
        let privateKey = try PrivateKey(data: Data(repeating: 0x02, count: 32))
        let lockingScript = Data([
            OP._DUP.rawValue,
            OP._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x01, count: 20) + [
            OP._EQUALVERIFY.rawValue,
            OP._CHECKSIG.rawValue
        ])
        
        let previousTransactionHash = Transaction.Hash(naturalOrder: Data(repeating: 0x00, count: 32))
        let unspent = Transaction.Output.Unspent(
            value: 10_000,
            lockingScript: lockingScript,
            previousTransactionHash: previousTransactionHash,
            previousTransactionOutputIndex: 0
        )
        
        let privateKeys: [Transaction.Output.Unspent: PrivateKey] = [unspent: privateKey]
        
        let recipientOutputs = [
            Transaction.Output(value: 6_000, lockingScript: Data([0x51])),
            Transaction.Output(value: 1_000, lockingScript: Data([0x52]))
        ]
        
        let changeScript = Data([
            OP._DUP.rawValue,
            OP._HASH160.rawValue,
            0x14
        ] + Array(repeating: 0x02, count: 20) + [
            OP._EQUALVERIFY.rawValue,
            OP._CHECKSIG.rawValue
        ])
        let changeOutput = Transaction.Output(value: 3_000, lockingScript: changeScript)
        
        return (privateKeys: privateKeys,
                recipientOutputs: recipientOutputs,
                changeOutput: changeOutput,
                inputTotal: unspent.value)
    }
}
