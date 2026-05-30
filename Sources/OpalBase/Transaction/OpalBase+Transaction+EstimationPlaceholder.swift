// OpalBase+Transaction+EstimationPlaceholder.swift

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
                             outputs: [Output],
                             version: UInt32 = 2,
                             lockTime: UInt32 = 0) throws -> Int {
        guard inputCount >= 0 else { throw OpalBase.Transaction.Error.cannotCreateTransaction }
        if inputCount == 0 {
            var writer = Data.Writer()
            writer.writeLittleEndian(version)
            writer.writeCompactSize(CompactSize(value: 0))
            writer.writeCompactSize(CompactSize(value: UInt64(outputs.count)))
            for output in outputs {
                writer.writeData(try output.encode())
            }
            writer.writeLittleEndian(lockTime)
            return writer.data.count
        }

        let placeholderHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0, count: 32))
        let templateInput = Input(previousTransactionHash: placeholderHash,
                                  previousTransactionOutputIndex: 0,
                                  unlockingScript: Data(),
                                  sequence: 0xFFFFFFFF)
        let inputs = Array(repeating: templateInput, count: inputCount)
        let transaction = OpalBase.Transaction(version: version, inputs: inputs, outputs: outputs, lockTime: lockTime)
        return try transaction.estimateSize()
    }
    
    static func estimateFee(inputCount: Int,
                            outputs: [Output],
                            feePerByte: UInt64,
                            version: UInt32 = 2,
                            lockTime: UInt32 = 0) throws -> UInt64 {
        let size = try estimateSize(inputCount: inputCount, outputs: outputs, version: version, lockTime: lockTime)
        return try makeFee(size: size, feePerByte: feePerByte)
    }
}

extension _OpalBase.Transaction {
    private enum EstimationInputTemplate {
        static let unlockingScript: Data = OpalBase.Transaction.Unlocker.p2pkh_CheckSig()
            .makePlaceholderUnlockingScript(signatureFormat: .schnorr)
    }
    
    func estimateSize() throws -> Int {
        try makeSerializedTransaction(with: makeInputsForEstimation()).count
    }
    
    private func makeInputsForEstimation() -> [Input] {
        inputs.map { input in
            guard input.unlockingScript.isEmpty else { return input }
            return Input(previousTransactionHash: input.previousTransactionHash,
                         previousTransactionOutputIndex: input.previousTransactionOutputIndex,
                         unlockingScript: EstimationInputTemplate.unlockingScript,
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
