// TransactionModel+OutputOrderingStrategyModel.swift

import Foundation
import OpalCrypto

extension TransactionModel {
    public static let minimumRelayFeeRate: UInt64 = 1
    public static let defaultFeeRate: UInt64 = minimumRelayFeeRate
    
    public enum OutputOrderingStrategyModel: Sendable {
        case privacyRandomized
        case canonicalBIP69
    }
    
    static func defaultPrivacyOutputShuffle(_ outputs: [OutputModel]) -> [OutputModel] {
        outputs.count > 1 ? outputs.shuffled() : outputs
    }
    
    static func build(version: UInt32 = 2,
                      utxoPrivateKeyPairs: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel],
                      recipientOutputs: [OutputModel],
                      changeOutput: OutputModel,
                      outputOrderingStrategy: OutputOrderingStrategyModel = .privacyRandomized,
                      signatureFormat: EllipticCurveDigitalSignatureAlgorithmModel.SignatureFormatModel = .schnorr,
                      feePerByte: UInt64 = 1,
                      sequence: UInt32 = 0xFFFFFFFF,
                      lockTime: UInt32 = 0,
                      shouldAllowDustDonation: Bool = false,
                      privacyOutputShuffle: ([OutputModel]) -> [OutputModel] = defaultPrivacyOutputShuffle,
                      unlockers: [TransactionModel.OutputModel.UnspentModel: UnlockerModel] = .init()) throws -> TransactionModel {
        let builder = BuilderModel(utxoPrivateKeyPairs: utxoPrivateKeyPairs,
                              signatureFormat: signatureFormat,
                              sequence: sequence,
                              unlockers: unlockers)
        
        let inputs = builder.makeInputs()
        let orderedRecipientOutputs = recipientOutputs
        
        let (outputs, _) = try computeOutputsAndFee(version: version,
                                                    inputs: inputs,
                                                    recipientOutputs: orderedRecipientOutputs,
                                                    changeOutput: changeOutput,
                                                    outputOrderingStrategy: outputOrderingStrategy,
                                                    feePerByte: feePerByte,
                                                    lockTime: lockTime,
                                                    shouldAllowDustDonation: shouldAllowDustDonation,
                                                    privacyOutputShuffle: privacyOutputShuffle)
        
        let unsignedTransaction = TransactionModel(version: version, inputs: inputs, outputs: outputs, lockTime: lockTime)
        let signedTransaction = try signTransaction(unsignedTransaction, using: builder)
        
        return try correctFeeAfterSigning(signedTransaction: signedTransaction,
                                          inputs: inputs,
                                          builder: builder,
                                          recipientOutputs: orderedRecipientOutputs,
                                          changeOutput: changeOutput,
                                          outputOrderingStrategy: outputOrderingStrategy,
                                          feePerByte: feePerByte,
                                          lockTime: lockTime,
                                          shouldAllowDustDonation: shouldAllowDustDonation,
                                          privacyOutputShuffle: privacyOutputShuffle)
    }
    
    private static func computeOutputsAndFee(version: UInt32,
                                             inputs: [InputModel],
                                             recipientOutputs: [OutputModel],
                                             changeOutput: OutputModel,
                                             outputOrderingStrategy: OutputOrderingStrategyModel,
                                             feePerByte: UInt64,
                                             lockTime: UInt32,
                                             shouldAllowDustDonation: Bool,
                                             privacyOutputShuffle: ([OutputModel]) -> [OutputModel]) throws -> ([OutputModel], UInt64) {
        let transactionWithChange = TransactionModel(version: version,
                                                inputs: inputs,
                                                outputs: recipientOutputs + [changeOutput],
                                                lockTime: lockTime)
        
        let estimatedFeeWithChange = try transactionWithChange.calculateFee(feePerByte: feePerByte)
        let changeAmount = changeOutput.value
        let minimumRelayFeeRate = TransactionModel.minimumRelayFeeRate
        let changeDustThreshold = try changeOutput.calculateDustThreshold(feeRate: minimumRelayFeeRate)
        
        var outputs = recipientOutputs
        var didRemoveChangeOutput = false
        
        if changeAmount < estimatedFeeWithChange {
            didRemoveChangeOutput = true
            
            let transactionWithoutChange = TransactionModel(version: version,
                                                       inputs: inputs,
                                                       outputs: recipientOutputs,
                                                       lockTime: lockTime)
            let estimatedFeeWithoutChange = try transactionWithoutChange.calculateFee(feePerByte: feePerByte)
            
            if changeAmount < estimatedFeeWithoutChange {
                if !shouldAllowDustDonation {
                    let requiredAdditionalAmount = estimatedFeeWithoutChange - changeAmount
                    throw Error.insufficientFunds(required: requiredAdditionalAmount)
                }
            } else {
                let donation = changeAmount - estimatedFeeWithoutChange
                if donation > 0 {
                    let additionalRequired = estimatedFeeWithChange - changeAmount
                    guard donation < changeDustThreshold else { throw Error.insufficientFunds(required: additionalRequired) }
                    guard shouldAllowDustDonation else { throw Error.outputValueIsLessThanTheDustLimit }
                }
            }
        } else {
            let remainingChange = changeAmount - estimatedFeeWithChange
            
            if remainingChange > 0 {
                if remainingChange < changeDustThreshold {
                    guard shouldAllowDustDonation else { throw Error.outputValueIsLessThanTheDustLimit }
                } else {
                    outputs.append(.init(value: remainingChange,
                                         lockingScript: changeOutput.lockingScript,
                                         tokenData: changeOutput.tokenData))
                }
            }
        }
        
        let orderedOutputs: [OutputModel]
        switch outputOrderingStrategy {
        case .privacyRandomized:
            orderedOutputs = privacyOutputShuffle(outputs)
        case .canonicalBIP69:
            orderedOutputs = OutputModel.applyBIP69Ordering(outputs)
        }
        
        let positiveValueOutputs = orderedOutputs.filter { $0.value > 0 }
        let totalPositiveOutput = positiveValueOutputs.map(\.value).reduce(0, +)
        guard !positiveValueOutputs.isEmpty else { throw Error.insufficientFunds(required: totalPositiveOutput) }
        for output in orderedOutputs where !output.isOpReturnScript {
            let dustThreshold = try output.calculateDustThreshold(feeRate: minimumRelayFeeRate)
            guard output.value >= dustThreshold else { throw Error.outputValueIsLessThanTheDustLimit }
        }
        
        let finalizedTransaction = TransactionModel(version: version,
                                               inputs: inputs,
                                               outputs: orderedOutputs,
                                               lockTime: lockTime)
        let finalizedFee = try finalizedTransaction.calculateFee(feePerByte: feePerByte)
        
        if shouldAllowDustDonation && didRemoveChangeOutput {
            guard changeAmount >= finalizedFee else {
                let requiredAdditionalAmount = finalizedFee - changeAmount
                throw Error.insufficientFunds(required: requiredAdditionalAmount)
            }
        }
        
        return (orderedOutputs, finalizedFee)
    }
    
    static func signTransaction(_ unsignedTransaction: TransactionModel,
                                using builder: BuilderModel) throws -> TransactionModel {
        switch builder.signatureFormat {
        case .ecdsa(.raw), .ecdsa(.compact):
            throw Error.unsupportedSignatureFormat
        default:
            break
        }
        
        var transaction = unsignedTransaction
        let spentOutputs = builder.orderedUnspentOutputs.map { unspentOutput in
            OutputModel(value: unspentOutput.value,
                   lockingScript: unspentOutput.lockingScript,
                   tokenData: unspentOutput.tokenData)
        }
        
        for (index, unspentOutput) in builder.orderedUnspentOutputs.enumerated() {
            guard let privateKey = builder.findPrivateKey(for: unspentOutput) else { throw Error.cannotCreateTransaction }
            let publicKey = try PublicKeyModel(privateKey: privateKey)
            let unlocker = builder.makeUnlocker(for: unspentOutput)
            
            switch unlocker {
            case .p2pkh_CheckSig(let hashType):
                let outputBeingSpent = OutputModel(value: unspentOutput.value,
                                              lockingScript: unspentOutput.lockingScript,
                                              tokenData: unspentOutput.tokenData)
                let preimage = try unsignedTransaction.generatePreimage(for: index,
                                                                        hashType: hashType,
                                                                        outputBeingSpent: outputBeingSpent,
                                                                        spentOutputs: spentOutputs)
                
                let message = EllipticCurveDigitalSignatureAlgorithmModel.MessageModel.makeDoubleSecureHashAlgorithm256(preimage)
                let signature = try EllipticCurveDigitalSignatureAlgorithmModel.sign(message: message,
                                               with: privateKey.rawData,
                                               in: builder.signatureFormat)
                let signatureWithType = signature + Data([UInt8(hashType.value)])
                let unlockingScript = Data.push(signatureWithType) + Data.push(publicKey.compressedData)
                
                transaction = try transaction.injectUnlockingScript(unlockingScript, inputIndex: index)
            case .p2pkh_CheckDataSig(let message):
                let messageBytes = message
                let message = EllipticCurveDigitalSignatureAlgorithmModel.MessageModel.makeSingleSecureHashAlgorithm256(messageBytes)
                let signature = try EllipticCurveDigitalSignatureAlgorithmModel.sign(message: message,
                                               with: privateKey.rawData,
                                               in: builder.signatureFormat)
                let unlockingSignature = Data.push(signature) + Data.push(messageBytes) + Data.push(publicKey.compressedData)
                
                transaction = try transaction.injectUnlockingScript(unlockingSignature, inputIndex: index)
            }
        }
        
        return transaction
    }
}
