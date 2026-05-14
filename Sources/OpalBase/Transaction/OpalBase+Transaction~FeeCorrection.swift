// OpalBase+Transaction~FeeCorrection.swift

import Foundation

extension _OpalBase.Transaction {
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
                                           shouldAllowDustDonation: Bool,
                                           privacyOutputShuffle: ([Output]) -> [Output] = defaultPrivacyOutputShuffle) throws -> [Output] {
        let changePool = changeOutputTemplate.value
        guard changePool >= targetFee else {
            throw Error.insufficientFunds(required: targetFee - changePool)
        }
        
        let desiredChange = changePool - targetFee
        var outputs = recipientOutputs
        let minimumRelayFeeRate = OpalBase.Transaction.minimumRelayFeeRate
        let changeDustThreshold = try changeOutputTemplate.calculateDustThreshold(feeRate: minimumRelayFeeRate)
        
        if desiredChange == 0 {
            if changeOutputTemplate.tokenData != nil {
                try validateDustDonationAllowed(for: changeOutputTemplate)
            }
        } else if desiredChange < changeDustThreshold {
            try validateDustDonationAllowed(for: changeOutputTemplate)
            guard shouldAllowDustDonation else { throw Error.outputValueIsLessThanTheDustLimit }
        } else {
            outputs.append(.init(value: desiredChange,
                                 lockingScript: changeOutputTemplate.lockingScript,
                                 tokenData: changeOutputTemplate.tokenData))
        }
        
        return try orderAndValidateOutputs(outputs,
                                           outputOrderingStrategy: outputOrderingStrategy,
                                           privacyOutputShuffle: privacyOutputShuffle)
    }
    
    static func correctFeeAfterSigning(signedTransaction: OpalBase.Transaction,
                                       inputs: [Input],
                                       builder: Builder,
                                       recipientOutputs: [Output],
                                       changeOutput: Output,
                                       outputOrderingStrategy: OutputOrderingStrategy,
                                       feePerByte: UInt64,
                                       lockTime: UInt32,
                                       shouldAllowDustDonation: Bool,
        privacyOutputShuffle: ([Output]) -> [Output] = defaultPrivacyOutputShuffle) throws -> OpalBase.Transaction {
        let inputTotal = try sumValues(of: builder.orderedUnspentOutputs) { $0.value }
        var correctedTransaction = signedTransaction
        let maximumPasses = 8
        
        for _ in 0..<maximumPasses {
            let requiredFee = try correctedTransaction.calculateRequiredFee(feePerByte: feePerByte)
            let outputTotal = try calculateTotalValue(for: correctedTransaction.outputs)
            let feePaid = try calculateFeePaid(inputTotal: inputTotal, outputTotal: outputTotal)
            
            guard feePaid != requiredFee else { return correctedTransaction }
            
            let correctedOutputs = try computeOutputsForTargetFee(recipientOutputs: recipientOutputs,
                                                                  changeOutputTemplate: changeOutput,
                                                                  outputOrderingStrategy: outputOrderingStrategy,
                                                                  targetFee: requiredFee,
                                                                  shouldAllowDustDonation: shouldAllowDustDonation,
                                                                  privacyOutputShuffle: privacyOutputShuffle)
            
            guard correctedOutputs != correctedTransaction.outputs else { return correctedTransaction }
            
            let unsignedTransaction = OpalBase.Transaction(version: correctedTransaction.version,
                                                  inputs: inputs,
                                                  outputs: correctedOutputs,
                                                  lockTime: lockTime)
            correctedTransaction = try signTransaction(unsignedTransaction, using: builder)
        }
        
        let finalRequiredFee = try correctedTransaction.calculateRequiredFee(feePerByte: feePerByte)
        let finalOutputTotal = try calculateTotalValue(for: correctedTransaction.outputs)
        let finalFeePaid = try calculateFeePaid(inputTotal: inputTotal, outputTotal: finalOutputTotal)
        
        guard finalFeePaid >= finalRequiredFee else {
            throw Error.insufficientFunds(required: finalRequiredFee - finalFeePaid)
        }
        
        let finalOutputs = try computeOutputsForTargetFee(recipientOutputs: recipientOutputs,
                                                          changeOutputTemplate: changeOutput,
                                                          outputOrderingStrategy: outputOrderingStrategy,
                                                          targetFee: finalRequiredFee,
                                                          shouldAllowDustDonation: shouldAllowDustDonation,
                                                          privacyOutputShuffle: privacyOutputShuffle)
        guard finalOutputs == correctedTransaction.outputs else {
            throw Error.cannotCreateTransaction
        }
        
        return correctedTransaction
    }
    
    static func sumValues<S: Sequence>(of values: S,
                                       _ transform: (S.Element) -> UInt64) throws -> UInt64 {
        try values.reduce(0) { partial, value in
            try partial.addOrThrow(transform(value), overflowError: Error.cannotCreateTransaction)
        }
    }

    static func orderAndValidateOutputs(_ outputs: [Output],
                                        outputOrderingStrategy: OutputOrderingStrategy,
                                        privacyOutputShuffle: ([Output]) -> [Output]) throws -> [Output] {
        let orderedOutputs: [Output]
        switch outputOrderingStrategy {
        case .privacyRandomized:
            orderedOutputs = privacyOutputShuffle(outputs)
        case .canonicalBIP69:
            orderedOutputs = Output.applyBIP69Ordering(outputs)
        }
        guard orderedOutputs.containsSameOutputs(as: outputs) else {
            throw Error.cannotCreateTransaction
        }

        var hasSpendableOutput = false
        var totalValue: UInt64 = 0
        for output in orderedOutputs where !output.isOpReturnScript {
            hasSpendableOutput = true
            totalValue = try totalValue.addOrThrow(output.value, overflowError: Error.cannotCreateTransaction)
            let dustThreshold = try output.calculateDustThreshold(feeRate: minimumRelayFeeRate)
            guard output.value >= dustThreshold else { throw Error.outputValueIsLessThanTheDustLimit }
        }
        guard hasSpendableOutput else { throw Error.insufficientFunds(required: 0) }

        return orderedOutputs
    }

    private static func calculateTotalValue(for outputs: [Output]) throws -> UInt64 {
        try sumValues(of: outputs) { $0.value }
    }
    
    private static func calculateFeePaid(inputTotal: UInt64, outputTotal: UInt64) throws -> UInt64 {
        guard inputTotal >= outputTotal else {
            throw Error.insufficientFunds(required: outputTotal - inputTotal)
        }
        
        return inputTotal - outputTotal
    }

    static func validateDustDonationAllowed(for changeOutput: Output) throws {
        guard changeOutput.tokenData == nil else {
            throw Error.outputValueIsLessThanTheDustLimit
        }
    }
}

private extension Array where Element == OpalBase.Transaction.Output {
    func containsSameOutputs(as expectedOutputs: [Element]) -> Bool {
        var remainingOutputs = expectedOutputs

        for output in self {
            guard let index = remainingOutputs.firstIndex(of: output) else {
                return false
            }
            remainingOutputs.remove(at: index)
        }

        return remainingOutputs.isEmpty
    }
}

extension _OpalBase.Transaction.Output {
    var isOpReturnScript: Bool {
        let returnOpcode = ScriptOperationCode._RETURN.rawValue
        if lockingScript.starts(with: [returnOpcode]) {
            return true
        }
        
        return lockingScript.starts(
            with: [ScriptOperationCode._0.rawValue, returnOpcode]
        )
    }
}
