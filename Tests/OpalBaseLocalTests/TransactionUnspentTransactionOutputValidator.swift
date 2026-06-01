// TransactionUnspentTransactionOutputValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Transaction UTXO", .tags(.unit, .transaction))
struct TransactionUnspentTransactionOutputValidator {
    @Test("unspent output initializer normalizes sliced locking script")
    func unspentOutputInitializerNormalizesSlicedLockingScript() {
        let lockingScript = Data([0x51, 0x21, 0x00])
        let paddedData = Data([0xff]) + lockingScript
        let slicedLockingScript = paddedData[paddedData.index(after: paddedData.startIndex)...]
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            value: 546,
            lockingScript: slicedLockingScript,
            previousTransactionHash: .init(naturalOrder: Data(repeating: 0x11, count: 32)),
            previousTransactionOutputIndex: 0
        )

        #expect(slicedLockingScript.startIndex != lockingScript.startIndex)
        #expect(unspentOutput.lockingScript == lockingScript)
        #expect(unspentOutput.lockingScript.startIndex == lockingScript.startIndex)
    }

    @Test("build preserves token metadata on change outputs")
    func buildPreservesTokenMetadataOnChangeOutputs() throws {
        let components = try makeTransactionBuilderComponents()
        let tokenData = try makeTokenData(fillByte: 0xA5, amount: 21)
        let tokenizedChangeOutput = OpalBase.Transaction.Output(
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
}
