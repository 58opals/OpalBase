// TransactionUnspentTransactionOutputValidator~Fixtures.swift

import Foundation
import OpalCrypto
@testable import OpalBase

extension TransactionUnspentTransactionOutputValidator {
    func makeTransactionBuilderComponents() throws -> (privateKeys: [OpalBase.Transaction.Output.Unspent: Data],
                                                       recipientOutputs: [OpalBase.Transaction.Output],
                                                       changeOutput: OpalBase.Transaction.Output,
                                                       inputTotal: UInt64) {
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
        
        return (privateKeys: privateKeys,
                recipientOutputs: recipientOutputs,
                changeOutput: changeOutput,
                inputTotal: unspent.value)
    }
    
    func makeTokenData(fillByte: UInt8, amount: UInt64) throws -> OpalBase.CashTokens.TokenData {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: fillByte, count: 32)
        )
        return OpalBase.CashTokens.TokenData(category: category, amount: amount, nft: nil)
    }
}
