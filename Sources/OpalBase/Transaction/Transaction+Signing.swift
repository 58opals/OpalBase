import Foundation

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
        
        // Transaction version
        preimage.append(contentsOf: withUnsafeBytes(of: version.littleEndian, Array.init))
        
        // Previous transaction outputs identifiers
        preimage.append(self.previousOutputsHash)
        
        // Transaction input sequence numbers
        preimage.append(self.sequenceHash)
        
        let input = inputs[index]
        
        // The identifier of the output being spent (previous transaction hash + previous transaction index)
        preimage.append(input.previousTransactionHash)
        preimage.append(contentsOf: withUnsafeBytes(of: input.previousTransactionOutputIndex.littleEndian, Array.init))
        
        // The locking script of the output being spent
        preimage.append(outputBeingSpent.lockingScriptLength.encode())
        preimage.append(outputBeingSpent.lockingScript)
        
        // The value of the output being spent
        preimage.append(contentsOf: withUnsafeBytes(of: outputBeingSpent.value.littleEndian, Array.init))
        
        // The sequence number of the transaction input
        preimage.append(contentsOf: withUnsafeBytes(of: input.sequence.littleEndian, Array.init))
        
        // The created transaction outputs
        preimage.append(self.outputsHash)
        
        // Transaction locktime
        preimage.append(contentsOf: withUnsafeBytes(of: lockTime.littleEndian, Array.init))
        
        // The signature hash type
        preimage.append(contentsOf: withUnsafeBytes(of: hashType.value.littleEndian, Array.init))
        
        return preimage
    }
    
    /// Computes the hash of all previous outputs.
    /// - Returns: The double SHA-256 hash of all previous outputs.
    private var previousOutputsHash: Data {
        var data = Data()
        for input in inputs {
            data.append(input.previousTransactionHash)
            data.append(contentsOf: withUnsafeBytes(of: input.previousTransactionOutputIndex.littleEndian, Array.init))
        }
        return data.sha256().sha256()
    }
    
    /// Computes the hash of all sequence numbers.
    /// - Returns: The double SHA-256 hash of all sequence numbers.
    private var sequenceHash: Data {
        var data = Data()
        for input in inputs {
            data.append(contentsOf: withUnsafeBytes(of: input.sequence.littleEndian, Array.init))
        }
        return data.sha256().sha256()
    }
    
    /// Computes the hash of all outputs.
    /// - Returns: The double SHA-256 hash of all outputs.
    private var outputsHash: Data {
        var data = Data()
        for output in outputs {
            data.append(output.encode())
        }
        return data.sha256().sha256()
    }
}

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
        let hash = preimage.sha256().sha256()
        
        var signature = try ECDSA.sign(message: hash, with: privateKey, in: format)
        switch format {
        case .der:
            signature.append(contentsOf: withUnsafeBytes(of: hashType.value.littleEndian, Array.init))
        case .schnorr:
            signature.append(UInt8(hashType.value & 0xFF))
        }
        
        return signature
    }
}

extension Transaction {
    /// Inserts the signature into the unlocking script of the specified input.
    /// - Parameters:
    ///   - signature: The signature to insert.
    ///   - index: The index of the input to modify.
    /// - Returns: A new transaction with the updated input.
    func addSignature(_ signature: Data, index: Int) -> Transaction {
        var newInputs = inputs
        let originalInput = newInputs[index]
        let newInput = Input(previousTransactionHash: originalInput.previousTransactionHash,
                             previousTransactionIndex: originalInput.previousTransactionOutputIndex,
                             unlockingScript: signature,
                             sequence: originalInput.sequence)
        newInputs[index] = newInput
        
        return Transaction(version: self.version,
                           inputs: newInputs,
                           outputs: self.outputs,
                           lockTime: self.lockTime)
    }
}
