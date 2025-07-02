// Transaction~Signing.swift

import Foundation

extension Transaction {
    /// Signs the transaction input with the given private key.
    /// - Parameters:
    ///   - privateKey: The private key for signing.
    ///   - index: The index of the input to sign.
    ///   - hashType: The hash type (e.g., SIGHASH_ALL).
    ///   - outputBeingSpent: The output being spent by this input.
    ///   - format: The signature format (ECDSA or Schnorr).
    /// - Returns: The generated signature.
    func signInput(privateKey: Data, index: Int, hashType: HashType, outputBeingSpent: Output, format: ECDSA.SignatureFormat) throws -> Data {
        let preimage = self.generatePreimage(for: index, hashType: hashType, outputBeingSpent: outputBeingSpent)
        let hash = SHA256.hash(preimage) // This is NOT DOUBLE-SHA256 hash. Do SHA256 hash only once to the preimage.
        let signature = try ECDSA.sign(message: hash, with: privateKey, in: format)
        
        return signature
    }
}

extension Transaction {
    /// Constructs the preimage for signing a specific input.
    /// - Parameters:
    ///   - index: The index of the input to sign.
    ///   - hashType: The hash type (e.g., SIGHASH_ALL).
    ///   - outputBeingSpent: The output being spent by this input.
    /// - Returns: The preimage data.
    func generatePreimage(for index: Int, hashType: HashType, outputBeingSpent: Output) -> Data {
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
        case .all(_):
            var data = Data()
            for output in outputs {
                data.append(output.encode())
            }
            transactionOutputsHash = HASH256.hash(data)
        case .none(_):
            transactionOutputsHash = Data(repeating: 0x00, count: 32)
        case .single(_):
            //if outputs.endIndex - 1 > index {
            if index < outputs.count {
                let outputWithTheSameIndexAsTheInputBeingSigned = outputs[index].encode()
                transactionOutputsHash = HASH256.hash(outputWithTheSameIndexAsTheInputBeingSigned)
            } else {
                transactionOutputsHash = Data(repeating: 0x00, count: 32)
            }
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

extension Transaction {
    enum HashType {
        case all(anyoneCanPay: Bool)
        case none(anyoneCanPay: Bool)
        case single(anyoneCanPay: Bool)
        
        enum Modifier: UInt32 {
            case forkId = 0x40
            case anyoneCanPay = 0x80
        }
        
        var value: UInt32 {
            var value: UInt32 = 0
            switch self {
            case .all(let anyoneCanPay):
                value = 0x01 | Modifier.forkId.rawValue | (anyoneCanPay ? Modifier.anyoneCanPay.rawValue : 0)
            case .none(let anyoneCanPay):
                value = 0x02 | Modifier.forkId.rawValue | (anyoneCanPay ? Modifier.anyoneCanPay.rawValue : 0)
            case .single(let anyoneCanPay):
                value = 0x03 | Modifier.forkId.rawValue | (anyoneCanPay ? Modifier.anyoneCanPay.rawValue : 0)
            }
            return value
        }
        
        var isAnyoneCanPay: Bool {
            switch self {
            case .all(let anyoneCanPay):
                if anyoneCanPay { return true }
                else { return false }
            case .none(let anyoneCanPay):
                if anyoneCanPay { return true }
                else { return false }
            case .single(let anyoneCanPay):
                if anyoneCanPay { return true }
                else { return false }
            }
        }
        
        var isNotAnyoneCanPayWithAllHashType: Bool {
            switch self {
            case .all(let anyoneCanPay):
                if anyoneCanPay { return false }
                else { return true }
            case .none(_):
                return false
            case .single(_):
                return false
            }
        }
    }
}
