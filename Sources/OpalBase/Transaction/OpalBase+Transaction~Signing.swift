// OpalBase+Transaction~Signing.swift

import Foundation
import OpalCrypto

extension _OpalBase.Transaction {
    /// Constructs the preimage for signing a specific input.
    /// - Parameters:
    ///   - index: The index of the input to sign.
    ///   - hashType: The hash type (e.g., SIGHASH_ALL).
    ///   - outputBeingSpent: The output being spent by this input.
    /// - Returns: The preimage data.
    func generatePreimage(
        for index: Int,
        hashType: HashType,
        outputBeingSpent: Output,
        spentOutputs: [Output]? = nil
    ) throws -> Data {
        guard inputs.indices.contains(index) else {
            throw OpalBase.Transaction.Error.sighashSingleIndexOutOfRange
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
            previousOutputsHash = OpalCryptoAdapter.hash256(data)
        }
        preimage.append(previousOutputsHash)
        
        if hashType.isUnspentTransactionOutputsEnabled {
            guard let spentOutputs else {
                throw OpalBase.Transaction.Error.missingUnspentTransactionOutputs
            }
            guard spentOutputs.count == inputs.count else {
                throw OpalBase.Transaction.Error.unspentTransactionOutputsCountMismatch(expected: inputs.count,
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
            sequenceNumbersHash = OpalCryptoAdapter.hash256(data)
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
            transactionOutputsHash = OpalCryptoAdapter.hash256(data)
        case .none:
            transactionOutputsHash = Data(repeating: 0x00, count: 32)
        case .single:
            let outputWithTheSameIndexAsTheInputBeingSigned = try outputs[index].encode()
            transactionOutputsHash = OpalCryptoAdapter.hash256(outputWithTheSameIndexAsTheInputBeingSigned)
        }
        preimage.append(transactionOutputsHash)
        
        let transactionLockTime = lockTime.littleEndianData
        preimage.append(transactionLockTime)
        
        let signatureHashType = hashType.value.littleEndianData
        preimage.append(signatureHashType)
        
        return preimage
    }
}

private extension _OpalBase.Transaction {
    func makeUnspentTransactionOutputsHash(from outputs: [Output]) throws -> Data {
        var data = Data()
        for output in outputs {
            data.append(try output.encode())
        }
        return OpalCryptoAdapter.hash256(data)
    }
}

extension _OpalBase.Transaction {
    func signInputInPlace(
        at index: Int,
        spending outputBeingSpent: Output,
        privateKey: Data,
        signatureFormat: OpalBase.Transaction.SignatureFormat,
        unlocker: OpalBase.Transaction.Unlocker,
        using templateTransaction: OpalBase.Transaction? = nil,
        spentOutputs: [Output]? = nil
    ) throws -> OpalBase.Transaction {
        if case .ecdsa(.raw) = signatureFormat {
            throw OpalBase.Transaction.Error.unsupportedSignatureFormat
        }

        let signingTransaction = templateTransaction ?? self
        let publicKey = try OpalBase.Key.PublicKey(privateKeyData: privateKey)
        let opalPrivateKey = try OpalCrypto.Secp256k1.PrivateKey(rawRepresentation: privateKey)

        switch unlocker {
        case .p2pkh_CheckSig(let hashType):
            let preimage = try signingTransaction.generatePreimage(
                for: index,
                hashType: hashType,
                outputBeingSpent: outputBeingSpent,
                spentOutputs: spentOutputs
            )
            let signatureDigest = signingTransaction.makeSignatureDigest(
                from: preimage,
                inputIndex: index,
                hashType: hashType
            )
            let typedSignatureDigest = try OpalCrypto.Signature.Digest(rawRepresentation: signatureDigest)
            let signature: Data = switch signatureFormat {
            case .ecdsa:
                try OpalCrypto.Signature.ECDSA.sign(
                    digest: typedSignatureDigest,
                    privateKey: opalPrivateKey,
                    format: signatureFormat.opalCryptoECDSAFormat!
                ).rawRepresentation
            case .schnorr:
                try OpalCrypto.Signature.Schnorr.sign(
                    digest: typedSignatureDigest,
                    privateKey: opalPrivateKey
                ).rawRepresentation
            }
            let signatureWithType = signature + Data([UInt8(hashType.value)])
            let unlockingScript = Data.push(signatureWithType) + Data.push(publicKey.compressedData)

            return try injectUnlockingScript(unlockingScript, inputIndex: index)
        case .p2pkh_CheckDataSig(let message):
            let signatureMessage: Data = switch signatureFormat {
            case .ecdsa:
                message
            case .schnorr:
                OpalCryptoAdapter.sha256(message)
            }
            let signature: Data = switch signatureFormat {
            case .ecdsa:
                try OpalCrypto.Signature.ECDSA.sign(
                    message: signatureMessage,
                    privateKey: opalPrivateKey,
                    format: signatureFormat.opalCryptoECDSAFormat!
                ).rawRepresentation
            case .schnorr:
                try OpalCrypto.Signature.Schnorr.sign(
                    digest: OpalCrypto.Signature.Digest(rawRepresentation: signatureMessage),
                    privateKey: opalPrivateKey
                ).rawRepresentation
            }
            let unlockingScript = Data.push(signature) + Data.push(message) + Data.push(publicKey.compressedData)

            return try injectUnlockingScript(unlockingScript, inputIndex: index)
        }
    }

    func signInputInPlace(
        at index: Int,
        spending unspentOutput: OpalBase.Transaction.Output.Unspent,
        privateKey: Data,
        signatureFormat: OpalBase.Transaction.SignatureFormat,
        unlocker: OpalBase.Transaction.Unlocker,
        using templateTransaction: OpalBase.Transaction? = nil,
        spentOutputs: [Output]? = nil
    ) throws -> OpalBase.Transaction {
        try signInputInPlace(
            at: index,
            spending: Output(
                value: unspentOutput.value,
                lockingScript: unspentOutput.lockingScript,
                tokenData: unspentOutput.tokenData
            ),
            privateKey: privateKey,
            signatureFormat: signatureFormat,
            unlocker: unlocker,
            using: templateTransaction,
            spentOutputs: spentOutputs
        )
    }

    /// Inserts the signature into the unlocking script of the specified input.
    /// - Parameters:
    ///   - signature: The signature to insert.
    ///   - index: The index of the input to modify.
    /// - Returns: A new transaction with the updated input.
    /// - Throws: `OpalBase.Transaction.Error.sighashSingleIndexOutOfRange` when the input index is invalid.
    func injectUnlockingScript(_ unlockingScript: Data, inputIndex: Int) throws -> OpalBase.Transaction {
        guard inputs.indices.contains(inputIndex) else {
            throw OpalBase.Transaction.Error.sighashSingleIndexOutOfRange
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
        
        return OpalBase.Transaction(
            version: self.version,
            inputs: newInputs,
            outputs: self.outputs,
            lockTime: self.lockTime
        )
    }

    private func makeSignatureDigest(
        from preimage: Data,
        inputIndex: Int,
        hashType: HashType
    ) -> Data {
        if hashType.mode == .single, inputIndex >= outputs.count {
            return preimage
        }
        return OpalCryptoAdapter.hash256(preimage)
    }
}
