// TransactionUnspentTransactionOutputValidator~Fixtures.swift

import Foundation
@testable import OpalBase

extension TransactionUnspentTransactionOutputValidator {
    func makeTransactionBuilderComponents() throws -> (privateKeys: [OpalBase.Transaction.OutputModel.Unspent: OpalBase.PrivateKey],
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
    
    func makeTokenData(fillByte: UInt8, amount: UInt64) throws -> OpalBase.CashTokens.TokenData {
        let category = try OpalBase.CashTokens.CategoryIDModel(
            transactionOrderData: Data(repeating: fillByte, count: 32)
        )
        return OpalBase.CashTokens.TokenData(category: category, amount: amount, nft: nil)
    }
}
