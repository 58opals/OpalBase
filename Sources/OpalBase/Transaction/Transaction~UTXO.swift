// Transaction~UTXO.swift

import Foundation

extension Transaction {
    public static let defaultFeeRate = UInt64(1)
    static var dustLimit: UInt64 { 546 }
    
    public enum OutputOrderingStrategy: Sendable {
        case privacyRandomized
        case canonicalBIP69
    }
    
    static func build(version: UInt32 = 2,
                      utxoPrivateKeyPairs: [Transaction.Output.Unspent: PrivateKey],
                      recipientOutputs: [Output],
                      changeOutput: Output,
                      outputOrderingStrategy: OutputOrderingStrategy = .privacyRandomized,
                      signatureFormat: ECDSA.SignatureFormat = .schnorr,
                      feePerByte: UInt64 = 1,
                      sequence: UInt32 = 0xFFFFFFFF,
                      lockTime: UInt32 = 0,
                      shouldAllowDustDonation: Bool = false,
                      unlockers: [Transaction.Output.Unspent: Unlocker] = .init()) throws -> Transaction {
        let builder = Builder(utxoPrivateKeyPairs: utxoPrivateKeyPairs,
                              signatureFormat: signatureFormat,
                              sequence: sequence,
                              unlockers: unlockers)
        
        let inputs = builder.makeInputs()
        
        let (outputs, _) = try computeOutputsAndFee(version: version,
                                                    inputs: inputs,
                                                    recipientOutputs: recipientOutputs,
                                                    changeOutput: changeOutput,
                                                    outputOrderingStrategy: outputOrderingStrategy,
                                                    feePerByte: feePerByte,
                                                    lockTime: lockTime,
                                                    shouldAllowDustDonation: shouldAllowDustDonation)
        
        let unsignedTransaction = Transaction(version: version, inputs: inputs, outputs: outputs, lockTime: lockTime)
        let signedTransaction = try signTransaction(unsignedTransaction, using: builder)
        
        return try correctFeeAfterSigning(signedTransaction: signedTransaction,
                                          inputs: inputs,
                                          builder: builder,
                                          recipientOutputs: recipientOutputs,
                                          changeOutput: changeOutput,
                                          outputOrderingStrategy: outputOrderingStrategy,
                                          feePerByte: feePerByte,
                                          lockTime: lockTime,
                                          shouldAllowDustDonation: shouldAllowDustDonation)
    }
    
    private static func computeOutputsAndFee(version: UInt32,
                                             inputs: [Input],
                                             recipientOutputs: [Output],
                                             changeOutput: Output,
                                             outputOrderingStrategy: OutputOrderingStrategy,
                                             feePerByte: UInt64,
                                             lockTime: UInt32,
                                             shouldAllowDustDonation: Bool) throws -> ([Output], UInt64) {
        let transactionWithChange = Transaction(version: version,
                                                inputs: inputs,
                                                outputs: recipientOutputs + [changeOutput],
                                                lockTime: lockTime)
        
        let estimatedFeeWithChange = try transactionWithChange.calculateFee(feePerByte: feePerByte)
        let changeAmount = changeOutput.value
        
        var outputs = recipientOutputs
        var didRemoveChangeOutput = false
        
        if changeAmount < estimatedFeeWithChange {
            didRemoveChangeOutput = true
            
            let transactionWithoutChange = Transaction(version: version,
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
                    guard donation < Transaction.dustLimit else { throw Error.insufficientFunds(required: additionalRequired) }
                    guard shouldAllowDustDonation else { throw Error.outputValueIsLessThanTheDustLimit }
                }
            }
        } else {
            let remainingChange = changeAmount - estimatedFeeWithChange
            
            if remainingChange > 0 {
                if remainingChange < Transaction.dustLimit {
                    guard shouldAllowDustDonation else { throw Error.outputValueIsLessThanTheDustLimit }
                } else {
                    outputs.append(.init(value: remainingChange, lockingScript: changeOutput.lockingScript))
                }
            }
        }
        
        let orderedOutputs: [Output]
        switch outputOrderingStrategy {
        case .privacyRandomized:
            orderedOutputs = outputs
        case .canonicalBIP69:
            orderedOutputs = Output.applyBIP69Ordering(outputs)
        }
        
        let positiveValueOutputs = orderedOutputs.filter { $0.value > 0 }
        let totalPositiveOutput = positiveValueOutputs.map(\.value).reduce(0, +)
        guard !positiveValueOutputs.isEmpty else { throw Error.insufficientFunds(required: totalPositiveOutput) }
        guard !orderedOutputs.contains(where: { !$0.isOpReturnScript && $0.value < Transaction.dustLimit })
        else { throw Error.outputValueIsLessThanTheDustLimit }
        
        let finalizedTransaction = Transaction(version: version,
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
    
    static func signTransaction(_ unsignedTransaction: Transaction,
                                using builder: Builder) throws -> Transaction {
        switch builder.signatureFormat {
        case .ecdsa(.raw), .ecdsa(.compact):
            throw Error.unsupportedSignatureFormat
        default:
            break
        }
        
        var transaction = unsignedTransaction
        
        for (index, unspentOutput) in builder.orderedUnspentOutputs.enumerated() {
            guard let privateKey = builder.findPrivateKey(for: unspentOutput) else { throw Error.cannotCreateTransaction }
            let publicKey = try PublicKey(privateKey: privateKey)
            let unlocker = builder.makeUnlocker(for: unspentOutput)
            
            switch unlocker {
            case .p2pkh_CheckSig(let hashType):
                let outputBeingSpent = Output(value: unspentOutput.value, lockingScript: unspentOutput.lockingScript)
                let preimage = try unsignedTransaction.generatePreimage(for: index,
                                                                        hashType: hashType,
                                                                        outputBeingSpent: outputBeingSpent)
                
                let message = ECDSA.Message.makeDoubleSHA256(preimage)
                let signature = try ECDSA.sign(message: message,
                                               with: privateKey,
                                               in: builder.signatureFormat)
                let signatureWithType = signature + Data([UInt8(hashType.value)])
                let unlockingScript = Data.push(signatureWithType) + Data.push(publicKey.compressedData)
                
                transaction = try transaction.injectUnlockingScript(unlockingScript, inputIndex: index)
            case .p2pkh_CheckDataSig(let message):
                let messageBytes = message
                let message = ECDSA.Message.makeSingleSHA256(messageBytes)
                let signature = try ECDSA.sign(message: message,
                                               with: privateKey,
                                               in: builder.signatureFormat)
                let unlockingSignature = Data.push(signature) + Data.push(messageBytes) + Data.push(publicKey.compressedData)
                
                transaction = try transaction.injectUnlockingScript(unlockingSignature, inputIndex: index)
            }
        }
        
        return transaction
    }
}
