// Transaction~Signing.swift

import Foundation

extension Transaction {
    /// Constructs the preimage for signing a specific input.
    /// - Parameters:
    ///   - index: The index of the input to sign.
    ///   - hashType: The hash type (e.g., SIGHASH_ALL).
    ///   - outputBeingSpent: The output being spent by this input.
    /// - Returns: The preimage data.
    func generatePreimage(
        for index: Int,
        hashType: HashType,
        outputBeingSpent: Output
    ) throws -> Data {
        guard inputs.indices.contains(index) else {
            throw Transaction.Error.sighashSingleIndexOutOfRange
        }
        
        let inputBeingSigned = inputs[index]
        
        if hashType.mode == .single, index >= outputs.count {
            var invalidIndexHash = Data(repeating: 0x00, count: 32)
            invalidIndexHash[0] = 0x01
            return invalidIndexHash
        }
        
        var preimage = Data()
        
        let transactionVersion = version.littleEndianData
        preimage.append(transactionVersion)
        
        var previousOutputsHash = Data()
        if hashType.isAnyoneCanPay {
            previousOutputsHash = Data(repeating: 0x00, count: 32)
        } else {
            var data = Data()
            for input in inputs {
                data.append(input.previousTransactionHash.naturalOrder)
                data.append(
                    input.previousTransactionOutputIndex.littleEndianData
                )
            }
            previousOutputsHash = HASH256.hash(data)
        }
        preimage.append(previousOutputsHash)
        
        var sequenceNumbersHash = Data()
        if hashType.isAllWithoutAnyoneCanPay {
            var data = Data()
            for input in inputs {
                data.append(input.sequence.littleEndianData)
            }
            sequenceNumbersHash = HASH256.hash(data)
        } else {
            sequenceNumbersHash = Data(repeating: 0x00, count: 32)
        }
        
        preimage.append(sequenceNumbersHash)
        
        let previousOutputHash = inputBeingSigned.previousTransactionHash
        preimage.append(previousOutputHash.naturalOrder)
        let previousOutputIndex = inputBeingSigned.previousTransactionOutputIndex
            .littleEndianData
        preimage.append(previousOutputIndex)
        
        let tokenPrefixData = try outputBeingSpent.makeTokenPrefixData()
        let coveredLockingScript = tokenPrefixData + outputBeingSpent.lockingScript
        let coveredLockingScriptLength = CompactSize(value: UInt64(coveredLockingScript.count)).encode()
        preimage.append(coveredLockingScriptLength)
        preimage.append(coveredLockingScript)
        
        let previousOutputValue = outputBeingSpent.value.littleEndianData
        preimage.append(previousOutputValue)
        
        let inputSequenceNumber = inputBeingSigned.sequence.littleEndianData
        preimage.append(inputSequenceNumber)
        
        var transactionOutputsHash = Data()
        switch hashType.mode {
        case .all:
            var data = Data()
            for output in outputs {
                data.append(try output.encode())
            }
            transactionOutputsHash = HASH256.hash(data)
        case .none:
            transactionOutputsHash = Data(repeating: 0x00, count: 32)
        case .single:
            let outputWithTheSameIndexAsTheInputBeingSigned = try outputs[index].encode()
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
    /// - Throws: `Transaction.Error.sighashSingleIndexOutOfRange` when the input index is invalid.
    func injectUnlockingScript(_ unlockingScript: Data, inputIndex: Int) throws -> Transaction {
        guard inputs.indices.contains(inputIndex) else {
            throw Transaction.Error.sighashSingleIndexOutOfRange
        }
        
        var newInputs = inputs
        
        let originalInput = newInputs[inputIndex]
        let newInput = Input(
            previousTransactionHash: originalInput.previousTransactionHash,
            previousTransactionOutputIndex: originalInput
                .previousTransactionOutputIndex,
            unlockingScript: unlockingScript,
            sequence: originalInput.sequence
        )
        newInputs[inputIndex] = newInput
        
        return Transaction(
            version: self.version,
            inputs: newInputs,
            outputs: self.outputs,
            lockTime: self.lockTime
        )
    }
}
