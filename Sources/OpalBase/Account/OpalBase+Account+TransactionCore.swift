// OpalBase+Account+TransactionCore.swift

import Foundation
import OpalCrypto

extension _OpalBase.Account {
    struct TransactionCore: Sendable {
        let transaction: OpalBase.Transaction
        let fee: OpalBase.Satoshi
        let bchChange: SpendPlan.TransactionResult.Change?
    }
    
    static func buildTransactionCore(
        privateKeys: [OpalBase.Transaction.Output.Unspent: Data],
        recipientOutputs: [OpalBase.Transaction.Output],
        changeOutput: OpalBase.Transaction.Output,
        feeRate: UInt64,
        shouldAllowDustDonation: Bool,
        shouldRandomizeRecipientOrdering: Bool,
        changeEntry: OpalBase.Address.Book.Entry,
        signatureFormat: OpalBase.Transaction.SignatureFormat,
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

        let recipientTotal = try recipientOutputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try OpalBase.Satoshi($0.value)
        }

        let bchChangeAmount: OpalBase.Satoshi
        do {
            bchChangeAmount = try totalOutput - recipientTotal
        } catch {
            throw mapBuildError(error)
        }
        
        let change: SpendPlan.TransactionResult.Change?
        do {
            change = try findBCHChange(in: transaction,
                                       changeEntry: changeEntry,
                                       amount: bchChangeAmount)
        } catch {
            throw mapBuildError(error)
        }
        
        return .init(transaction: transaction, fee: fee, bchChange: change)
    }
    
    private static func findBCHChange(
        in transaction: OpalBase.Transaction,
        changeEntry: OpalBase.Address.Book.Entry,
        amount: OpalBase.Satoshi
    ) throws -> SpendPlan.TransactionResult.Change? {
        guard amount.uint64 > 0 else { return nil }

        let lockingScript = changeEntry.address.lockingScript.data
        
        guard transaction.outputs.contains(where: {
            $0.lockingScript == lockingScript
                && $0.tokenData == nil
                && $0.value == amount.uint64
        }) else {
            throw OpalBase.Transaction.Error.cannotCreateTransaction
        }
        
        return .init(entry: changeEntry, amount: amount)
    }
}
