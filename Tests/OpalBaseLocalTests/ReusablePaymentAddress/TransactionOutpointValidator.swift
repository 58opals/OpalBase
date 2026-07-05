// TransactionOutpointValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Transaction outpoint", .tags(.unit))
struct TransactionOutpointValidator {
    @Test("outpoint preserves hash and output index")
    func preserveHashAndOutputIndex() {
        let hash = ReusablePaymentAddressFixtureData.makeTransactionHash(byte: 9)
        let outpoint = OpalBase.Transaction.Outpoint(
            transactionHash: hash,
            outputIndex: 2
        )

        #expect(outpoint.transactionHash == hash)
        #expect(outpoint.outputIndex == 2)
    }

    @Test("outpoint initializes from transaction inputs and unspent outputs")
    func initializeFromInputsAndUnspentOutputs() {
        let hash = ReusablePaymentAddressFixtureData.makeTransactionHash(byte: 10)
        let input = OpalBase.Transaction.Input(
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 4,
            unlockingScript: Data([0x51])
        )
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            value: 1_000,
            lockingScript: Data([0x51]),
            previousTransactionHash: hash,
            previousTransactionOutputIndex: 4
        )

        #expect(OpalBase.Transaction.Outpoint(input) == OpalBase.Transaction.Outpoint(unspentOutput))
    }
}
