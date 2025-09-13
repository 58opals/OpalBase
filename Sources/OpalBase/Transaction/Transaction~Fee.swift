// Transaction~Fee.swift

import Foundation

extension Transaction {
    func calculateFee(feePerByte: UInt64 = 1) -> UInt64 {
        let size = self.estimatedSize()
        return UInt64(size) * feePerByte
    }
}

// MARK: - Centralized estimators for selection and building
extension Transaction {
    static func estimatedSize(inputCount: Int,
                              outputs: [Output],
                              version: UInt32 = 2,
                              lockTime: UInt32 = 0) -> Int {
        guard inputCount >= 0 else { return 0 }
        let placeholderHash = Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let templateInput = Input(previousTransactionHash: placeholderHash,
                                  previousTransactionOutputIndex: 0,
                                  unlockingScript: Data(),
                                  sequence: 0xFFFFFFFF)
        let inputs = Array(repeating: templateInput, count: inputCount)
        let transaction = Transaction(version: version, inputs: inputs, outputs: outputs, lockTime: lockTime)
        return transaction.estimatedSize()
    }
    
    static func estimatedFee(inputCount: Int,
                             outputs: [Output],
                             feePerByte: UInt64,
                             version: UInt32 = 2,
                             lockTime: UInt32 = 0) -> UInt64 {
        let size = estimatedSize(inputCount: inputCount, outputs: outputs, version: version, lockTime: lockTime)
        return UInt64(size) * feePerByte
    }
}

extension Transaction {
    func estimatedSize() -> Int {
        var size = 0
        
        size += 4 // version (4 bytes)
        size += 4 // locktime (4 bytes)
        size += CompactSize(value: UInt64(inputs.count)).encodedSize
        size += CompactSize(value: UInt64(outputs.count)).encodedSize
        
        inputs.forEach { size += $0.estimatedSize() }
        outputs.forEach { size += $0.estimatedSize() }
        
        return size
    }
}

extension Transaction.Input {
    func estimatedSize() -> Int {
        var size = 0
        
        size += 32 // previous transaction hash (32 bytes)
        size += 4 // previous transaction output index (4 bytes)
        size += 4 // sequence (4 bytes)
        let unlockingScriptSize = unlockingScript.isEmpty ? (1 + 72 + 1 + 33) : unlockingScript.count
        size += CompactSize(value: UInt64(unlockingScriptSize)).encodedSize
        size += unlockingScriptSize
        
        return size
    }
}

extension Transaction.Output {
    func estimatedSize() -> Int {
        var size = 0
        
        size += 8 // value (8 bytes)
        size += CompactSize(value: UInt64(lockingScript.count)).encodedSize
        size += lockingScript.count
        
        return size
    }
}

extension CompactSize {
    var encodedSize: Int {
        switch self {
        case .uint8: return 1
        case .uint16: return 3
        case .uint32: return 5
        case .uint64: return 9
        }
    }
}
