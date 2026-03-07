// OpalBase.Transaction+EstimationPlaceholderModel.swift

import Foundation

extension _OpalBase.Transaction {
    func calculateFee(feePerByte: UInt64 = 1) throws -> UInt64 {
        let size = try estimateSize()
        return try Self.makeFee(size: size, feePerByte: feePerByte)
    }
}

// MARK: - Centralized estimators for selection and building
extension _OpalBase.Transaction {
    static func estimateSize(inputCount: Int,
                             outputs: [OutputModel],
                             version: UInt32 = 2,
                             lockTime: UInt32 = 0) throws -> Int {
        guard inputCount >= 0 else { return 0 }
        let placeholderHash = OpalBase.Transaction.HashModel(naturalOrder: Data(repeating: 0, count: 32))
        let templateInput = InputModel(previousTransactionHash: placeholderHash,
                                  previousTransactionOutputIndex: 0,
                                  unlockingScript: Data(),
                                  sequence: 0xFFFFFFFF)
        let inputs = Array(repeating: templateInput, count: inputCount)
        let transaction = OpalBase.Transaction(version: version, inputs: inputs, outputs: outputs, lockTime: lockTime)
        return try transaction.estimateSize()
    }
    
    static func estimateFee(inputCount: Int,
                            outputs: [OutputModel],
                            feePerByte: UInt64,
                            version: UInt32 = 2,
                            lockTime: UInt32 = 0) throws -> UInt64 {
        let size = try estimateSize(inputCount: inputCount, outputs: outputs, version: version, lockTime: lockTime)
        return try makeFee(size: size, feePerByte: feePerByte)
    }
}

extension _OpalBase.Transaction {
    private enum EstimationPlaceholderModel {
        static let unlockingScript: Data = OpalBase.Transaction.UnlockerModel.p2pkh_CheckSig()
            .makePlaceholderUnlockingScript(signatureFormat: .schnorr)
    }
    
    func estimateSize() throws -> Int {
        try makeSerializedTransaction(with: makeInputsForEstimation()).count
    }
    
    private func makeInputsForEstimation() -> [InputModel] {
        inputs.map { input in
            guard input.unlockingScript.isEmpty else { return input }
            return InputModel(previousTransactionHash: input.previousTransactionHash,
                         previousTransactionOutputIndex: input.previousTransactionOutputIndex,
                         unlockingScript: EstimationPlaceholderModel.unlockingScript,
                         sequence: input.sequence)
        }
        
    }
}

extension _OpalBase.Transaction {
    static func makeFee(size: Int, feePerByte: UInt64) throws -> UInt64 {
        guard size >= 0 else { throw OpalBase.Transaction.Error.feeCalculationOverflow(size: size, feePerByte: feePerByte) }
        
        let byteCount = UInt64(size)
        let (fee, overflow) = byteCount.multipliedReportingOverflow(by: feePerByte)
        guard !overflow else { throw OpalBase.Transaction.Error.feeCalculationOverflow(size: size, feePerByte: feePerByte) }
        
        return fee
    }
}

// MARK: - LegacyModel reference implementation
/// Retained for documentation, this version of the fee utilities omits helper placeholders so readers can see the raw sizing logic. It works alongside the legacy `OpalBase.Transaction` snippet above to paint a complete picture of how virtual sizes and fees were previously calculated.

private extension _OpalBase.Transaction {
    func estimateSize_Legacy() -> Int {
        var size = 0
        
        size += 4 // version (4 bytes)
        size += 4 // locktime (4 bytes)
        size += CompactSizeModel(value: UInt64(inputs.count)).encodedSize_Legacy
        size += CompactSizeModel(value: UInt64(outputs.count)).encodedSize_Legacy
        
        inputs.forEach { size += $0.estimateSize_Legacy() }
        outputs.forEach { size += $0.estimateSize_Legacy() }
        
        return size
    }
}

private extension _OpalBase.Transaction.InputModel {
    func estimateSize_Legacy() -> Int {
        var size = 0
        
        size += 32 // previous transaction hash (32 bytes)
        size += 4 // previous transaction output index (4 bytes)
        size += 4 // sequence (4 bytes)
        let unlockingScriptSize = unlockingScript.isEmpty ? (1 + 64 + 1 + 33) : unlockingScript.count
        size += CompactSizeModel(value: UInt64(unlockingScriptSize)).encodedSize_Legacy
        size += unlockingScriptSize
        
        return size
    }
}

private extension _OpalBase.Transaction.OutputModel {
    func estimateSize_Legacy() -> Int {
        var size = 0
        
        size += 8 // value (8 bytes)
        size += CompactSizeModel(value: UInt64(lockingScript.count)).encodedSize_Legacy
        size += lockingScript.count
        
        return size
    }
}

private extension CompactSizeModel {
    var encodedSize_Legacy: Int {
        switch self {
        case .uint8: return 1
        case .uint16: return 3
        case .uint32: return 5
        case .uint64: return 9
        }
    }
}

