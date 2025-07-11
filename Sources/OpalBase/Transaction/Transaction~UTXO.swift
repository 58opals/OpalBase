// Transaction~UTXO.swift

import Foundation

extension Transaction {
    static let defaultFeeRate = UInt64(1)
    static var dustLimit: UInt64 { 546 }
    
    static func createTransaction(version: UInt32 = 2,
                                  utxoPrivateKeyPairs: [Transaction.Output.Unspent: PrivateKey],
                                  recipientOutputs: [Output],
                                  changeOutput: Output,
                                  signatureFormat: ECDSA.SignatureFormat = .ecdsa(.der),
                                  feePerByte: UInt64 = 1,
                                  sequence: UInt32 = 0xFFFFFFFF,
                                  lockTime: UInt32 = 0,
                                  allowDustDonation: Bool = false) throws -> Transaction {
        var inputs: [Input] = []
        
        let utxos = utxoPrivateKeyPairs.keys
        for utxo in utxos {
            let temporaryInput = Input(previousTransactionHash: utxo.previousTransactionHash,
                                       previousTransactionOutputIndex: utxo.previousTransactionOutputIndex,
                                       unlockingScript: Data(),
                                       sequence: sequence)
            inputs.append(temporaryInput)
        }
        
        let temporaryTransactionWithoutFee = Transaction(version: version, inputs: inputs, outputs: recipientOutputs + [changeOutput], lockTime: lockTime)
        
        let estimatedFee = temporaryTransactionWithoutFee.calculateFee(feePerByte: feePerByte)
        let oldChangeAmount = changeOutput.value
        guard oldChangeAmount >= estimatedFee else { throw Error.insufficientFunds(required: oldChangeAmount) }
        
        let newChangeAmount = oldChangeAmount - estimatedFee
        
        var outputs = recipientOutputs
        if newChangeAmount > 0 {
            if newChangeAmount < Transaction.dustLimit {
                guard allowDustDonation else { throw Error.outputValueIsLessThanTheDustLimit }
            } else {
                outputs.append(.init(value: newChangeAmount, lockingScript: changeOutput.lockingScript))
            }
        }
        
        let combinedOutputs = outputs.filter { $0.value > 0 }
        guard !combinedOutputs.isEmpty else { throw Error.insufficientFunds(required: combinedOutputs.map{$0.value}.reduce(0, +)) }
        guard !combinedOutputs.contains(where: { $0.value < Transaction.dustLimit }) else { throw Error.outputValueIsLessThanTheDustLimit }
        
        let temporaryTransactionWithFee = Transaction(version: version, inputs: inputs, outputs: combinedOutputs, lockTime: lockTime)
        
        var transaction = temporaryTransactionWithFee
        for (index, pair) in utxoPrivateKeyPairs.enumerated() {
            let utxo = pair.key
            let privateKey = pair.value
            let outputBeingSpent = Output(value: utxo.value, lockingScript: utxo.lockingScript)
            
            let hashType = HashType.all(anyoneCanPay: false)
            let signature = try temporaryTransactionWithFee.signInput(privateKey: privateKey.rawData,
                                                                      index: index,
                                                                      hashType: hashType,
                                                                      outputBeingSpent: outputBeingSpent,
                                                                      format: signatureFormat)
            
            let appendedHashType = switch signatureFormat {
            case .ecdsa(let ecdsa):
                switch ecdsa {
                case .der: Data([UInt8(hashType.value)])
                default: throw Error.unsupportedHashType
                }
            case .schnorr:
                throw Error.unsupportedSignatureFormat
            }
            
            let signatureWithHashType = signature + appendedHashType
            let sizeOfSignatureWithHashType = CompactSize(value: .init(signatureWithHashType.count)).encode()
            
            let compressedPublicKeyData = try PublicKey(privateKey: privateKey).compressedData
            let sizeOfPublicKey = CompactSize(value: .init(compressedPublicKeyData.count)).encode()
            
            let unlockingScript = sizeOfSignatureWithHashType + signatureWithHashType + sizeOfPublicKey + compressedPublicKeyData
            
            transaction = transaction.injectUnlockingScript(unlockingScript, inputIndex: index)
        }
        
        return transaction
    }
}
