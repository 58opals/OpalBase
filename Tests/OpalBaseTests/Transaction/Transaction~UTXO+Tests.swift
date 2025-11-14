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
}
