// OpalBase+Account+TransactionCore.swift

import Foundation
import OpalCrypto

extension _OpalBase.Account {
    struct TransactionCore: Sendable {
        let transaction: OpalBase.Transaction
        let fee: OpalBase.Satoshi
        let bitcoinCashChange: SpendPlan.TransactionResult.Change?
    }
    
    static func buildTransactionCore(
        privateKeys: [OpalBase.Transaction.Output.Unspent: Data],
        recipientOutputs: [OpalBase.Transaction.Output],
        changeOutput: OpalBase.Transaction.Output,
        feeRate: UInt64,
        shouldAllowDustDonation: Bool,
        shouldRandomizeRecipientOrdering: Bool,
        changeEntry: OpalBase.Address.Book.Entry,
        signatureFormat: OpalCrypto.Signature.Format,
        unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker],
        mapBuildError: (Swift.Error) -> OpalBase.Account.Error
    ) throws -> TransactionCore {
        let outputOrderingStrategy: OpalBase.Transaction.OutputOrderingStrategy = shouldRandomizeRecipientOrdering
        ? .privacyRandomized
        : .canonicalBIP69
        
        let transaction: OpalBase.Transaction
        do {
            transaction = try OpalBase.Transaction.build(
                utxoPrivateKeyPairs: privateKeys,
                recipientOutputs: recipientOutputs,
                changeOutput: changeOutput,
                outputOrderingStrategy: outputOrderingStrategy,
                signatureFormat: signatureFormat,
                feePerByte: feeRate,
                shouldAllowDustDonation: shouldAllowDustDonation,
                unlockers: unlockers
            )
        } catch {
            throw mapBuildError(error)
        }
        
        let totalOutput = try transaction.outputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try OpalBase.Satoshi($0.value)
        }
        
        let inputTotal = try privateKeys.keys.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try OpalBase.Satoshi($0.value)
        }
        
        let fee: OpalBase.Satoshi
        do {
            fee = try inputTotal - totalOutput
        } catch {
            throw Error.paymentExceedsMaximumAmount
        }
        
        let change: SpendPlan.TransactionResult.Change?
        do {
            change = try findBitcoinCashChange(in: transaction, changeEntry: changeEntry)
        } catch {
            throw mapBuildError(error)
        }
        
        return .init(transaction: transaction, fee: fee, bitcoinCashChange: change)
    }
    
    private static func findBitcoinCashChange(
        in transaction: OpalBase.Transaction,
        changeEntry: OpalBase.Address.Book.Entry
    ) throws -> SpendPlan.TransactionResult.Change? {
        let lockingScript = changeEntry.address.lockingScript.data
        
        guard let output = transaction.outputs.first(where: {
            $0.lockingScript == lockingScript && $0.tokenData == nil && $0.value > 0
        }) else {
            return nil
        }
        
        return .init(entry: changeEntry, amount: try OpalBase.Satoshi(output.value))
    }
}
