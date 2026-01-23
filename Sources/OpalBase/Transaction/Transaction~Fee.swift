// Transaction~Fee.swift

import Foundation

extension Transaction {
    func calculateFee(feePerByte: UInt64 = 1) throws -> UInt64 {
        let size = estimateSize()
        return try Self.makeFee(size: size, feePerByte: feePerByte)
    }
}

// MARK: - Centralized estimators for selection and building
extension Transaction {
    static func estimateSize(inputCount: Int,
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
        return transaction.estimateSize()
    }
    
    static func estimateFee(inputCount: Int,
                            outputs: [Output],
                            feePerByte: UInt64,
                            version: UInt32 = 2,
                            lockTime: UInt32 = 0) throws -> UInt64 {
        let size = estimateSize(inputCount: inputCount, outputs: outputs, version: version, lockTime: lockTime)
        return try makeFee(size: size, feePerByte: feePerByte)
    }
}

extension Transaction {
    private enum EstimationPlaceholder {
        static let unlockingScript: Data = Transaction.Unlocker.p2pkh_CheckSig()
            .makePlaceholderUnlockingScript(signatureFormat: .schnorr)
    }
    
    func estimateSize() -> Int {
        makeSerializedTransaction(with: makeInputsForEstimation()).count
    }
    
    private func makeInputsForEstimation() -> [Input] {
        inputs.map { input in
            guard input.unlockingScript.isEmpty else { return input }
            return Input(previousTransactionHash: input.previousTransactionHash,
                         previousTransactionOutputIndex: input.previousTransactionOutputIndex,
                         unlockingScript: EstimationPlaceholder.unlockingScript,
                         sequence: input.sequence)
        }
        
    }
}

extension Transaction {
    static func makeFee(size: Int, feePerByte: UInt64) throws -> UInt64 {
        guard size >= 0 else { throw Transaction.Error.feeCalculationOverflow(size: size, feePerByte: feePerByte) }
        
        let byteCount = UInt64(size)
        let (fee, overflow) = byteCount.multipliedReportingOverflow(by: feePerByte)
        guard !overflow else { throw Transaction.Error.feeCalculationOverflow(size: size, feePerByte: feePerByte) }
        
        return fee
    }
}

// MARK: - Legacy reference implementation
/// Retained for documentation, this version of the fee utilities omits helper placeholders so readers can see the raw sizing logic. It works alongside the legacy `Transaction` snippet above to paint a complete picture of how virtual sizes and fees were previously calculated.

private extension Transaction {
    func estimateSize_Legacy() -> Int {
        var size = 0
        
        size += 4 // version (4 bytes)
        size += 4 // locktime (4 bytes)
        size += CompactSize(value: UInt64(inputs.count)).encodedSize_Legacy
        size += CompactSize(value: UInt64(outputs.count)).encodedSize_Legacy
        
        inputs.forEach { size += $0.estimateSize_Legacy() }
        outputs.forEach { size += $0.estimateSize_Legacy() }
        
        return size
    }
}

private extension Transaction.Input {
    func estimateSize_Legacy() -> Int {
        var size = 0
        
        size += 32 // previous transaction hash (32 bytes)
        size += 4 // previous transaction output index (4 bytes)
        size += 4 // sequence (4 bytes)
        let unlockingScriptSize = unlockingScript.isEmpty ? (1 + 64 + 1 + 33) : unlockingScript.count
        size += CompactSize(value: UInt64(unlockingScriptSize)).encodedSize_Legacy
        size += unlockingScriptSize
        
        return size
    }
}

private extension Transaction.Output {
    func estimateSize_Legacy() -> Int {
        var size = 0
        
        size += 8 // value (8 bytes)
        size += CompactSize(value: UInt64(lockingScript.count)).encodedSize_Legacy
        size += lockingScript.count
        
        return size
    }
}

private extension CompactSize {
    var encodedSize_Legacy: Int {
        switch self {
        case .uint8: return 1
        case .uint16: return 3
        case .uint32: return 5
        case .uint64: return 9
        }
    }
}
