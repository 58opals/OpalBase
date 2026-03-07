// TransactionUnspentTransactionOutputValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Transaction UTXO", .tags(.unit, .transaction))
struct TransactionUnspentTransactionOutputValidator {
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
}
