// TransactionModel~FeeCorrection.swift

import Foundation

extension TransactionModel {
    func calculateActualSize() throws -> Int {
        try encode().count
    }
    
    func calculateRequiredFee(feePerByte: UInt64) throws -> UInt64 {
        let size = try calculateActualSize()
        return try Self.makeFee(size: size, feePerByte: feePerByte)
    }
    
    static func computeOutputsForTargetFee(recipientOutputs: [OutputModel],
                                           changeOutputTemplate: OutputModel,
                                           outputOrderingStrategy: OutputOrderingStrategyModel,
                                           targetFee: UInt64,
                                           shouldAllowDustDonation: Bool) throws -> [OutputModel] {
        let changePool = changeOutputTemplate.value
        guard changePool >= targetFee else {
            throw Error.insufficientFunds(required: targetFee - changePool)
        }
        
        let desiredChange = changePool - targetFee
        var outputs = recipientOutputs
        let minimumRelayFeeRate = TransactionModel.minimumRelayFeeRate
        let changeDustThreshold = try changeOutputTemplate.calculateDustThreshold(feeRate: minimumRelayFeeRate)
        
        if desiredChange == 0 {
            // No change output needed.
        } else if desiredChange < changeDustThreshold {
            guard shouldAllowDustDonation else { throw Error.outputValueIsLessThanTheDustLimit }
        } else {
            outputs.append(.init(value: desiredChange, lockingScript: changeOutputTemplate.lockingScript))
        }
        
        let orderedOutputs: [OutputModel]
        switch outputOrderingStrategy {
        case .privacyRandomized:
            orderedOutputs = outputs
        case .canonicalBIP69:
            orderedOutputs = OutputModel.applyBIP69Ordering(outputs)
        }
        
        let positiveValueOutputs = orderedOutputs.filter { $0.value > 0 }
        let totalPositiveOutput = positiveValueOutputs.map(\.value).reduce(0, +)
        guard !positiveValueOutputs.isEmpty else { throw Error.insufficientFunds(required: totalPositiveOutput) }
        for output in orderedOutputs where !output.isOpReturnScript {
            let dustThreshold = try output.calculateDustThreshold(feeRate: minimumRelayFeeRate)
            guard output.value >= dustThreshold else { throw Error.outputValueIsLessThanTheDustLimit }
        }
        
        return orderedOutputs
    }
    
    static func correctFeeAfterSigning(signedTransaction: TransactionModel,
                                       inputs: [InputModel],
                                       builder: BuilderModel,
                                       recipientOutputs: [OutputModel],
                                       changeOutput: OutputModel,
                                       outputOrderingStrategy: OutputOrderingStrategyModel,
                                       feePerByte: UInt64,
                                       lockTime: UInt32,
                                       shouldAllowDustDonation: Bool) throws -> TransactionModel {
        let inputTotal = builder.orderedUnspentOutputs.map(\.value).reduce(0, +)
        let firstSignedTransaction = signedTransaction
        var correctedTransaction = signedTransaction
        let maximumPasses = 8
        
        for _ in 0..<maximumPasses {
            let requiredFee = try correctedTransaction.calculateRequiredFee(feePerByte: feePerByte)
            let outputTotal = calculateTotalValue(for: correctedTransaction.outputs)
            let feePaid = inputTotal - outputTotal
            
            guard feePaid != requiredFee else { return correctedTransaction }
            
            let correctedOutputs = try computeOutputsForTargetFee(recipientOutputs: recipientOutputs,
                                                                  changeOutputTemplate: changeOutput,
                                                                  outputOrderingStrategy: outputOrderingStrategy,
                                                                  targetFee: requiredFee,
                                                                  shouldAllowDustDonation: shouldAllowDustDonation)
            
            guard correctedOutputs != correctedTransaction.outputs else { return correctedTransaction }
            
            let unsignedTransaction = TransactionModel(version: correctedTransaction.version,
                                                  inputs: inputs,
                                                  outputs: correctedOutputs,
                                                  lockTime: lockTime)
            correctedTransaction = try signTransaction(unsignedTransaction, using: builder)
        }
        
        let finalRequiredFee = try correctedTransaction.calculateRequiredFee(feePerByte: feePerByte)
        let finalOutputTotal = calculateTotalValue(for: correctedTransaction.outputs)
        let finalFeePaid = inputTotal - finalOutputTotal
        
        guard finalFeePaid >= finalRequiredFee else { return firstSignedTransaction }
        
        return correctedTransaction
    }
    
    private static func calculateTotalValue(for outputs: [OutputModel]) -> UInt64 {
        outputs.map(\.value).reduce(0, +)
    }
}

extension TransactionModel.OutputModel {
    var isOpReturnScript: Bool {
        guard let opcode = lockingScript.first else { return false }
        return opcode == ScriptOperationCodeModel._RETURN.rawValue
    }
}
