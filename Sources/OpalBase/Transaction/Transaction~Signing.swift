// Transaction~Signing.swift

import Foundation

extension Transaction {
    /// Constructs the preimage for signing a specific input.
    /// - Parameters:
    ///   - index: The index of the input to sign.
    ///   - hashType: The hash type (e.g., SIGHASH_ALL).
    ///   - outputBeingSpent: The output being spent by this input.
    /// - Returns: The preimage data.
    func generatePreimage(for index: Int, hashType: HashType, outputBeingSpent: Output) throws -> Data {
        if case .single = hashType, index >= outputs.count { throw Transaction.Error.sighashSingleIndexOutOfRange }
        
        var preimage = Data()
        
        let transactionVersion = version.littleEndianData
        preimage.append(transactionVersion)
        
        var previousOutputsHash = Data()
        if hashType.isAnyoneCanPay { previousOutputsHash = Data(repeating: 0x00, count: 32) }
        else {
            var data = Data()
            for input in inputs {
                data.append(input.previousTransactionHash.naturalOrder)
                data.append(input.previousTransactionOutputIndex.littleEndianData)
            }
            previousOutputsHash = HASH256.hash(data)
        }
        preimage.append(previousOutputsHash)
        
        var sequenceNumbersHash = Data()
        if hashType.isNotAnyoneCanPayWithAllHashType {
            var data = Data()
            for input in inputs {
                data.append(input.sequence.littleEndianData)
            }
            sequenceNumbersHash = HASH256.hash(data)
        } else {
            sequenceNumbersHash = Data(repeating: 0x00, count: 32)
        }
        
        preimage.append(sequenceNumbersHash)
        
        let previousOutputHash = inputs[index].previousTransactionHash
        preimage.append(previousOutputHash.naturalOrder)
        let previousOutputIndex = inputs[index].previousTransactionOutputIndex.littleEndianData
        preimage.append(previousOutputIndex)
        
        let modifiedLockingScriptLength = outputBeingSpent.lockingScriptLength.encode()
        preimage.append(modifiedLockingScriptLength)
        let modifiedLockingScript = outputBeingSpent.lockingScript
        preimage.append(modifiedLockingScript)
        
        let previousOutputValue = outputBeingSpent.value.littleEndianData
        preimage.append(previousOutputValue)
        
        let inputSequenceNumber = inputs[index].sequence.littleEndianData
        preimage.append(inputSequenceNumber)
        
        var transactionOutputsHash = Data()
        switch hashType {
        case .all:
            var data = Data()
            for output in outputs {
                data.append(output.encode())
            }
            transactionOutputsHash = HASH256.hash(data)
        case .none:
            transactionOutputsHash = Data(repeating: 0x00, count: 32)
        case .single:
            let outputWithTheSameIndexAsTheInputBeingSigned = outputs[index].encode()
            transactionOutputsHash = HASH256.hash(outputWithTheSameIndexAsTheInputBeingSigned)
        }
        preimage.append(transactionOutputsHash)
        
        let transactionLockTime = lockTime.littleEndianData
        preimage.append(transactionLockTime)
        
        let signatureHashType = hashType.value.littleEndianData
        preimage.append(signatureHashType)
        
        return preimage
    }
}

extension Transaction {
    /// Inserts the signature into the unlocking script of the specified input.
    /// - Parameters:
    ///   - signature: The signature to insert.
    ///   - index: The index of the input to modify.
    /// - Returns: A new transaction with the updated input.
    func injectUnlockingScript(_ unlockingScript: Data, inputIndex: Int) -> Transaction {
        var newInputs = inputs
        
        let originalInput = newInputs[inputIndex]
        let newInput = Input(previousTransactionHash: originalInput.previousTransactionHash,
                             previousTransactionOutputIndex: originalInput.previousTransactionOutputIndex,
                             unlockingScript: unlockingScript,
                             sequence: originalInput.sequence)
        newInputs[inputIndex] = newInput
        
        return Transaction(version: self.version,
                           inputs: newInputs,
                           outputs: self.outputs,
                           lockTime: self.lockTime)
    }
}
