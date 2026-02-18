// Account+TransactionCore.swift

import Foundation

extension Account {
    struct TransactionCore: Sendable {
        let transaction: Transaction
        let fee: Satoshi
        let bitcoinCashChange: SpendPlan.TransactionResult.Change?
    }
    
    static func buildTransactionCore(
        privateKeys: [Transaction.Output.Unspent: PrivateKey],
        recipientOutputs: [Transaction.Output],
        changeOutput: Transaction.Output,
        feeRate: UInt64,
        shouldAllowDustDonation: Bool,
        shouldRandomizeRecipientOrdering: Bool,
        changeEntry: Address.Book.Entry,
        signatureFormat: ECDSA.SignatureFormat,
        unlockers: [Transaction.Output.Unspent: Transaction.Unlocker],
        mapBuildError: (Swift.Error) -> Account.Error
    ) throws -> TransactionCore {
        let outputOrderingStrategy: Transaction.OutputOrderingStrategy = shouldRandomizeRecipientOrdering
        ? .privacyRandomized
        : .canonicalBIP69
        
        let transaction: Transaction
        do {
            transaction = try Transaction.build(
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
            try Satoshi($0.value)
        }
        
        let inputTotal = try privateKeys.keys.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try Satoshi($0.value)
        }
        
        let fee: Satoshi
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
        in transaction: Transaction,
        changeEntry: Address.Book.Entry
    ) throws -> SpendPlan.TransactionResult.Change? {
        let lockingScript = changeEntry.address.lockingScript.data
        
        guard let output = transaction.outputs.first(where: {
            $0.lockingScript == lockingScript && $0.tokenData == nil && $0.value > 0
        }) else {
            return nil
        }
        
        return .init(entry: changeEntry, amount: try Satoshi(output.value))
    }
}
