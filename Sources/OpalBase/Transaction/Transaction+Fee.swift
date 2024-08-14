import Foundation

extension Transaction {
    func calculateFee(feePerByte: UInt64 = 1) -> UInt64 {
        let size = self.estimatedSize()
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
