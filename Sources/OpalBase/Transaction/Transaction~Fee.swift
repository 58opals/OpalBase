// Transaction~Fee.swift

import Foundation

extension Transaction {
    func calculateFee(feePerByte: UInt64 = 1) -> UInt64 {
        let size = self.estimateSize()
        return UInt64(size) * feePerByte
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
                            lockTime: UInt32 = 0) -> UInt64 {
        let size = estimateSize(inputCount: inputCount, outputs: outputs, version: version, lockTime: lockTime)
        return UInt64(size) * feePerByte
    }
}

extension Transaction {
    private enum EstimationPlaceholder {
        static let unlockingScript: Data = Transaction.Unlocker.p2pkh_CheckSig()
            .makePlaceholderUnlockingScript(signatureFormat: .ecdsa(.der))
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
