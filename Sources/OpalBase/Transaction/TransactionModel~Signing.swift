// TransactionModel~Signing.swift

import Foundation
import OpalCrypto

extension TransactionModel {
    /// Constructs the preimage for signing a specific input.
    /// - Parameters:
    ///   - index: The index of the input to sign.
    ///   - hashType: The hash type (e.g., SIGHASH_ALL).
    ///   - outputBeingSpent: The output being spent by this input.
    /// - Returns: The preimage data.
    func generatePreimage(
        for index: Int,
        hashType: HashTypeModel,
        outputBeingSpent: OutputModel,
        spentOutputs: [OutputModel]? = nil
    ) throws -> Data {
        guard inputs.indices.contains(index) else {
            throw TransactionModel.Error.sighashSingleIndexOutOfRange
        }
        
        try hashType.validate()
        
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
            previousOutputsHash = SecureHash256Model.hash(data)
        }
        preimage.append(previousOutputsHash)
        
        if hashType.isUnspentTransactionOutputsEnabled {
            guard let spentOutputs else {
                throw TransactionModel.Error.missingUnspentTransactionOutputs
            }
            guard spentOutputs.count == inputs.count else {
                throw TransactionModel.Error.unspentTransactionOutputsCountMismatch(expected: inputs.count,
                                                                               actual: spentOutputs.count)
            }
            let unspentTransactionOutputsHash = try makeUnspentTransactionOutputsHash(from: spentOutputs)
            preimage.append(unspentTransactionOutputsHash)
        }
        
        var sequenceNumbersHash = Data()
        if hashType.isAllWithoutAnyoneCanPay {
            var data = Data()
            for input in inputs {
                data.append(input.sequence.littleEndianData)
            }
            sequenceNumbersHash = SecureHash256Model.hash(data)
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
        let coveredLockingScriptLength = CompactSizeModel(value: UInt64(coveredLockingScript.count)).encode()
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
            transactionOutputsHash = SecureHash256Model.hash(data)
        case .none:
            transactionOutputsHash = Data(repeating: 0x00, count: 32)
        case .single:
            let outputWithTheSameIndexAsTheInputBeingSigned = try outputs[index].encode()
            transactionOutputsHash = SecureHash256Model.hash(outputWithTheSameIndexAsTheInputBeingSigned)
        }
        preimage.append(transactionOutputsHash)
        
        let transactionLockTime = lockTime.littleEndianData
        preimage.append(transactionLockTime)
        
        let signatureHashType = hashType.value.littleEndianData
        preimage.append(signatureHashType)
        
        return preimage
    }
}

private extension TransactionModel {
    func makeUnspentTransactionOutputsHash(from outputs: [OutputModel]) throws -> Data {
        var data = Data()
        for output in outputs {
            data.append(try output.encode())
        }
        return SecureHash256Model.hash(data)
    }
}

extension TransactionModel {
    /// Inserts the signature into the unlocking script of the specified input.
    /// - Parameters:
    ///   - signature: The signature to insert.
    ///   - index: The index of the input to modify.
    /// - Returns: A new transaction with the updated input.
    /// - Throws: `TransactionModel.Error.sighashSingleIndexOutOfRange` when the input index is invalid.
    func injectUnlockingScript(_ unlockingScript: Data, inputIndex: Int) throws -> TransactionModel {
        guard inputs.indices.contains(inputIndex) else {
            throw TransactionModel.Error.sighashSingleIndexOutOfRange
        }
        
        var newInputs = inputs
        
        let originalInput = newInputs[inputIndex]
        let newInput = InputModel(
            previousTransactionHash: originalInput.previousTransactionHash,
            previousTransactionOutputIndex: originalInput
                .previousTransactionOutputIndex,
            unlockingScript: unlockingScript,
            sequence: originalInput.sequence
        )
        newInputs[inputIndex] = newInput
        
        return TransactionModel(
            version: self.version,
            inputs: newInputs,
            outputs: self.outputs,
            lockTime: self.lockTime
        )
    }
}
