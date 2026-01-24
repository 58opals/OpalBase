// Transaction~FeeCorrection.swift

import Foundation

extension Transaction {
    func calculateActualSize() throws -> Int {
        try encode().count
    }
    
    func calculateRequiredFee(feePerByte: UInt64) throws -> UInt64 {
        let size = try calculateActualSize()
        return try Self.makeFee(size: size, feePerByte: feePerByte)
    }
    
    static func computeOutputsForTargetFee(recipientOutputs: [Output],
                                           changeOutputTemplate: Output,
                                           outputOrderingStrategy: OutputOrderingStrategy,
                                           targetFee: UInt64,
                                           shouldAllowDustDonation: Bool) throws -> [Output] {
        let changePool = changeOutputTemplate.value
        guard changePool >= targetFee else {
            throw Error.insufficientFunds(required: targetFee - changePool)
        }
        
        let desiredChange = changePool - targetFee
        var outputs = recipientOutputs
        
        if desiredChange == 0 {
            // No change output needed.
        } else if desiredChange < Transaction.dustLimit {
            guard shouldAllowDustDonation else { throw Error.outputValueIsLessThanTheDustLimit }
        } else {
            outputs.append(.init(value: desiredChange, lockingScript: changeOutputTemplate.lockingScript))
        }
        
        let orderedOutputs: [Output]
        switch outputOrderingStrategy {
        case .privacyRandomized:
            orderedOutputs = outputs
        case .canonicalBIP69:
            orderedOutputs = Output.applyBIP69Ordering(outputs)
        }
        
        let positiveValueOutputs = orderedOutputs.filter { $0.value > 0 }
        let totalPositiveOutput = positiveValueOutputs.map(\.value).reduce(0, +)
        guard !positiveValueOutputs.isEmpty else { throw Error.insufficientFunds(required: totalPositiveOutput) }
        guard !orderedOutputs.contains(where: { !$0.isOpReturnScript && $0.value < Transaction.dustLimit })
        else { throw Error.outputValueIsLessThanTheDustLimit }
        
        return orderedOutputs
    }
    
    static func correctFeeAfterSigning(signedTransaction: Transaction,
                                       inputs: [Input],
                                       builder: Builder,
                                       recipientOutputs: [Output],
                                       changeOutput: Output,
                                       outputOrderingStrategy: OutputOrderingStrategy,
                                       feePerByte: UInt64,
                                       lockTime: UInt32,
                                       shouldAllowDustDonation: Bool) throws -> Transaction {
        let inputTotal = builder.orderedUnspentOutputs.map(\.value).reduce(0, +)
        let firstSignedTransaction = signedTransaction
        var correctedTransaction = signedTransaction
        let maximumPasses = 3
        
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
            
            let unsignedTransaction = Transaction(version: correctedTransaction.version,
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
    
    private static func calculateTotalValue(for outputs: [Output]) -> UInt64 {
        outputs.map(\.value).reduce(0, +)
    }
}

extension Transaction.Output {
    var isOpReturnScript: Bool {
        guard let opcode = lockingScript.first else { return false }
        return opcode == OP._RETURN.rawValue
    }
}
