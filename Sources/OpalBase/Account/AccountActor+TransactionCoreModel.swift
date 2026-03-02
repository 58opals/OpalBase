// AccountActor+TransactionCoreModel.swift

import Foundation
import OpalCrypto

extension AccountActor {
    struct TransactionCoreModel: Sendable {
        let transaction: TransactionModel
        let fee: SatoshiModel
        let bitcoinCashChange: SpendPlanModel.TransactionResult.Change?
    }
    
    static func buildTransactionCore(
        privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel],
        recipientOutputs: [TransactionModel.OutputModel],
        changeOutput: TransactionModel.OutputModel,
        feeRate: UInt64,
        shouldAllowDustDonation: Bool,
        shouldRandomizeRecipientOrdering: Bool,
        changeEntry: AddressModel.BookActor.EntryModel,
        signatureFormat: EllipticCurveDigitalSignatureAlgorithmModel.SignatureFormatModel,
        unlockers: [TransactionModel.OutputModel.UnspentModel: TransactionModel.UnlockerModel],
        mapBuildError: (Swift.Error) -> AccountActor.Error
    ) throws -> TransactionCoreModel {
        let outputOrderingStrategy: TransactionModel.OutputOrderingStrategyModel = shouldRandomizeRecipientOrdering
        ? .privacyRandomized
        : .canonicalBIP69
        
        let transaction: TransactionModel
        do {
            transaction = try TransactionModel.build(
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
            try SatoshiModel($0.value)
        }
        
        let inputTotal = try privateKeys.keys.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try SatoshiModel($0.value)
        }
        
        let fee: SatoshiModel
        do {
            fee = try inputTotal - totalOutput
        } catch {
            throw Error.paymentExceedsMaximumAmount
        }
        
        let change: SpendPlanModel.TransactionResult.Change?
        do {
            change = try findBitcoinCashChange(in: transaction, changeEntry: changeEntry)
        } catch {
            throw mapBuildError(error)
        }
        
        return .init(transaction: transaction, fee: fee, bitcoinCashChange: change)
    }
    
    private static func findBitcoinCashChange(
        in transaction: TransactionModel,
        changeEntry: AddressModel.BookActor.EntryModel
    ) throws -> SpendPlanModel.TransactionResult.Change? {
        let lockingScript = changeEntry.address.lockingScript.data
        
        guard let output = transaction.outputs.first(where: {
            $0.lockingScript == lockingScript && $0.tokenData == nil && $0.value > 0
        }) else {
            return nil
        }
        
        return .init(entry: changeEntry, amount: try SatoshiModel(output.value))
    }
}
