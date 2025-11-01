// Transaction~UnspentTransactionOutput.swift

import Foundation

extension Transaction {
    public static let defaultFeeRate = UInt64(1)
    static var dustLimit: UInt64 { 546 }
    
    static func build(version: UInt32 = 2,
                      unspentTransactionOutputPrivateKeyPairs: [Transaction.Output.Unspent: PrivateKey],
                      recipientOutputs: [Output],
                      changeOutput: Output,
                      signatureFormat: ECDSA.SignatureFormat = .ecdsa(.der),
                      feePerByte: UInt64 = 1,
                      sequence: UInt32 = 0xFFFFFFFF,
                      lockTime: UInt32 = 0,
                      shouldAllowDustDonation: Bool = false,
                      unlockers: [Transaction.Output.Unspent: Unlocker] = .init()) throws -> Transaction {
        let orderedUnspentTransactionOutputs = unspentTransactionOutputPrivateKeyPairs.keys.sorted {
            $0.previousTransactionOutputIndex < $1.previousTransactionOutputIndex
        }
        
        let inputs = orderedUnspentTransactionOutputs.map { unspentTransactionOutput in
            let unlocker = unlockers[unspentTransactionOutput] ?? .p2pkh_CheckSig()
            let placeholder = unlocker.makePlaceholderUnlockingScript(signatureFormat: signatureFormat)
            return Input(previousTransactionHash: unspentTransactionOutput.previousTransactionHash,
                         previousTransactionOutputIndex: unspentTransactionOutput.previousTransactionOutputIndex,
                         unlockingScript: placeholder,
                         sequence: sequence)
        }
        
        let temporaryTransactionWithoutFee = Transaction(version: version, inputs: inputs, outputs: recipientOutputs + [changeOutput], lockTime: lockTime)
        
        let estimatedFee = temporaryTransactionWithoutFee.calculateFee(feePerByte: feePerByte)
        let oldChangeAmount = changeOutput.value
        guard oldChangeAmount >= estimatedFee else { throw Error.insufficientFunds(required: oldChangeAmount) }
        
        let newChangeAmount = oldChangeAmount - estimatedFee
        
        var outputs = recipientOutputs
        if newChangeAmount > 0 {
            if newChangeAmount < Transaction.dustLimit {
                guard shouldAllowDustDonation else { throw Error.outputValueIsLessThanTheDustLimit }
            } else {
                outputs.append(.init(value: newChangeAmount, lockingScript: changeOutput.lockingScript))
            }
        }
        
        let combinedOutputs = outputs.filter { $0.value > 0 }
        guard !combinedOutputs.isEmpty else { throw Error.insufficientFunds(required: combinedOutputs.map{$0.value}.reduce(0, +)) }
        guard !combinedOutputs.contains(where: { $0.value < Transaction.dustLimit }) else { throw Error.outputValueIsLessThanTheDustLimit }
        
        let temporaryTransactionWithFee = Transaction(version: version, inputs: inputs, outputs: combinedOutputs, lockTime: lockTime)
        
        var transaction = temporaryTransactionWithFee
        for (index, unspentTransactionOutput) in orderedUnspentTransactionOutputs.enumerated() {
            guard let privateKey = unspentTransactionOutputPrivateKeyPairs[unspentTransactionOutput] else { throw Error.cannotCreateTransaction }
            let publicKey = try PublicKey(privateKey: privateKey)
            let mode = unlockers[unspentTransactionOutput] ?? .p2pkh_CheckSig()
            
            switch signatureFormat {
            case .ecdsa(.raw), .ecdsa(.compact):
                throw Error.unsupportedSignatureFormat
            default:
                break
            }
            
            switch mode {
            case .p2pkh_CheckSig(let hashType):
                let outputBeingSpent = Output(value: unspentTransactionOutput.value, lockingScript: unspentTransactionOutput.lockingScript)
                let preimage = try temporaryTransactionWithFee.generatePreimage(for: index,
                                                                                hashType: hashType,
                                                                                outputBeingSpent: outputBeingSpent)
                
                let message = SHA256.hash(preimage)
                // MARK: ↑ We hash the preimage "ONCE" here.
                /// The signer `(P256K.Signing.PrivateKey.signature(for:))` applies SHA256 again internally.
                /// Final digest signed = double‑SHA256(preimage).
                
                let signature = try ECDSA.sign(message: message,
                                               with: privateKey,
                                               in: signatureFormat)
                let signatureWithType = signature + Data([UInt8(hashType.value)])
                let unlockingScript = Data.push(signatureWithType) + Data.push(publicKey.compressedData)
                
                transaction = transaction.injectUnlockingScript(unlockingScript, inputIndex: index)
            case .p2pkh_CheckDataSig(let message):
                let message = message
                // MARK: ↑ We DO NOT hash the message here.
                /// The signer `(P256K.Signing.PrivateKey.signature(for:))` applies SHA256 once internally.
                /// Final digest signed = single‑SHA256(preimage).
                
                let signature = try ECDSA.sign(message: message,
                                               with: privateKey,
                                               in: signatureFormat)
                let unlockingSignature = Data.push(signature) + Data.push(message) + Data.push(publicKey.compressedData)
                
                transaction = transaction.injectUnlockingScript(unlockingSignature, inputIndex: index)
            }
        }
        
        return transaction
    }
}
