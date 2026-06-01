// OpalBase+Transaction+OutputOrderingStrategy.swift

import Foundation

extension _OpalBase.Transaction {
    public static let minimumRelayFeeRate: UInt64 = 1
    public static let defaultFeeRate: UInt64 = minimumRelayFeeRate

    public enum OutputOrderingStrategy: Sendable {
        case privacyRandomized
        case canonicalBIP69
    }

    static func defaultPrivacyOutputShuffle(_ outputs: [Output]) -> [Output] {
        outputs.count > 1 ? outputs.shuffled() : outputs
    }

    static func build(version: UInt32 = 2,
                      utxoPrivateKeyPairs: [OpalBase.Transaction.Output.Unspent: Data],
                      recipientOutputs: [Output],
                      changeOutput: Output,
                      outputOrderingStrategy: OutputOrderingStrategy = .privacyRandomized,
                      signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
                      feePerByte: UInt64 = 1,
                      sequence: UInt32 = 0xFFFFFFFF,
                      lockTime: UInt32 = 0,
                      shouldAllowDustDonation: Bool = false,
                      privacyOutputShuffle: ([Output]) -> [Output] = defaultPrivacyOutputShuffle,
                      unlockers: [OpalBase.Transaction.Output.Unspent: Unlocker] = .init()) throws -> OpalBase.Transaction {
        var privacyOutputShuffleCache: [[Output.Fingerprint]: [Output]] = .init()
        var privacyOutputOrder: [Output.Fingerprint]?
        let stablePrivacyOutputShuffle: ([Output]) -> [Output] = { outputs in
            let fingerprint = outputs.map(\.fingerprint)
            if let cachedOutputs = privacyOutputShuffleCache[fingerprint] {
                return cachedOutputs
            }

            let shuffledOutputs: [Output]
            if let privacyOutputOrder {
                var consumedIndexes: Set<Int> = .init()
                var orderedOutputs: [Output] = .init()
                orderedOutputs.reserveCapacity(outputs.count)

                for outputFingerprint in privacyOutputOrder {
                    let exactIndex = outputs.indices.first { index in
                        !consumedIndexes.contains(index) && outputs[index].fingerprint == outputFingerprint
                    }
                    let fallbackIndex = exactIndex ?? outputs.indices.first { index in
                        !consumedIndexes.contains(index) && outputs[index].orderingFingerprint == outputFingerprint.orderingFingerprint
                    }

                    guard let index = fallbackIndex else {
                        continue
                    }
                    consumedIndexes.insert(index)
                    orderedOutputs.append(outputs[index])
                }

                let remainingOutputs = outputs.indices.compactMap { index in
                    consumedIndexes.contains(index) ? nil : outputs[index]
                }
                shuffledOutputs = orderedOutputs + remainingOutputs
            } else {
                shuffledOutputs = privacyOutputShuffle(outputs)
                privacyOutputOrder = shuffledOutputs.map(\.fingerprint)
            }

            privacyOutputShuffleCache[fingerprint] = shuffledOutputs
            return shuffledOutputs
        }
        let builder = Builder(utxoPrivateKeyPairs: utxoPrivateKeyPairs,
                              signatureFormat: signatureFormat,
                              sequence: sequence,
                              unlockers: unlockers)

        let inputs = builder.makeInputs()

        let (outputs, _) = try computeOutputsAndFee(version: version,
                                                    inputs: inputs,
                                                    recipientOutputs: recipientOutputs,
                                                    changeOutput: changeOutput,
                                                    outputOrderingStrategy: outputOrderingStrategy,
                                                    feePerByte: feePerByte,
                                                    lockTime: lockTime,
                                                    shouldAllowDustDonation: shouldAllowDustDonation,
                                                    privacyOutputShuffle: stablePrivacyOutputShuffle)

        let unsignedTransaction = OpalBase.Transaction(version: version, inputs: inputs, outputs: outputs, lockTime: lockTime)
        let signedTransaction = try signTransaction(unsignedTransaction, using: builder)

        return try correctFeeAfterSigning(signedTransaction: signedTransaction,
                                          inputs: inputs,
                                          builder: builder,
                                          recipientOutputs: recipientOutputs,
                                          changeOutput: changeOutput,
                                          outputOrderingStrategy: outputOrderingStrategy,
                                          feePerByte: feePerByte,
                                          lockTime: lockTime,
                                          shouldAllowDustDonation: shouldAllowDustDonation,
                                          privacyOutputShuffle: stablePrivacyOutputShuffle)
    }

    private static func computeOutputsAndFee(version: UInt32,
                                             inputs: [Input],
                                             recipientOutputs: [Output],
                                             changeOutput: Output,
                                             outputOrderingStrategy: OutputOrderingStrategy,
                                             feePerByte: UInt64,
                                             lockTime: UInt32,
                                             shouldAllowDustDonation: Bool,
                                             privacyOutputShuffle: ([Output]) -> [Output]) throws -> ([Output], UInt64) {
        let transactionWithChange = OpalBase.Transaction(version: version,
                                                inputs: inputs,
                                                outputs: recipientOutputs + [changeOutput],
                                                lockTime: lockTime)

        let estimatedFeeWithChange = try transactionWithChange.calculateFee(feePerByte: feePerByte)
        let changeAmount = changeOutput.value
        let minimumRelayFeeRate = OpalBase.Transaction.minimumRelayFeeRate
        let changeDustThreshold = try changeOutput.calculateDustThreshold(feeRate: minimumRelayFeeRate)

        var outputs = recipientOutputs
        var didRemoveChangeOutput = false

        if changeAmount < estimatedFeeWithChange {
            didRemoveChangeOutput = true
            try validateDustDonationAllowed(for: changeOutput)

            let transactionWithoutChange = OpalBase.Transaction(version: version,
                                                       inputs: inputs,
                                                       outputs: recipientOutputs,
                                                       lockTime: lockTime)
            let estimatedFeeWithoutChange = try transactionWithoutChange.calculateFee(feePerByte: feePerByte)

            if changeAmount < estimatedFeeWithoutChange {
                if !shouldAllowDustDonation {
                    let requiredAdditionalAmount = estimatedFeeWithoutChange - changeAmount
                    throw Error.insufficientFunds(required: requiredAdditionalAmount)
                }
            } else {
                let donation = changeAmount - estimatedFeeWithoutChange
                if donation > 0 {
                    let additionalRequired = estimatedFeeWithChange - changeAmount
                    guard donation < changeDustThreshold else { throw Error.insufficientFunds(required: additionalRequired) }
                    guard shouldAllowDustDonation else { throw Error.outputValueIsLessThanTheDustLimit }
                }
            }
        } else {
            let remainingChange = changeAmount - estimatedFeeWithChange

            if remainingChange > 0 {
                if remainingChange < changeDustThreshold {
                    try validateDustDonationAllowed(for: changeOutput)
                    guard shouldAllowDustDonation else { throw Error.outputValueIsLessThanTheDustLimit }
                } else {
                    outputs.append(makeChangeOutput(value: remainingChange, from: changeOutput))
                }
            } else if changeOutput.tokenData != nil {
                try validateDustDonationAllowed(for: changeOutput)
            }
        }

        let orderedOutputs = try orderAndValidateOutputs(outputs,
                                                         outputOrderingStrategy: outputOrderingStrategy,
                                                         privacyOutputShuffle: privacyOutputShuffle)

        let finalizedTransaction = OpalBase.Transaction(version: version,
                                               inputs: inputs,
                                               outputs: orderedOutputs,
                                               lockTime: lockTime)
        let finalizedFee = try finalizedTransaction.calculateFee(feePerByte: feePerByte)

        if shouldAllowDustDonation && didRemoveChangeOutput {
            guard changeAmount >= finalizedFee else {
                let requiredAdditionalAmount = finalizedFee - changeAmount
                throw Error.insufficientFunds(required: requiredAdditionalAmount)
            }
        }

        return (orderedOutputs, finalizedFee)
    }

    static func signTransaction(_ unsignedTransaction: OpalBase.Transaction,
                                using builder: Builder) throws -> OpalBase.Transaction {
        var transaction = unsignedTransaction
        let spentOutputs = builder.orderedUnspentOutputs.map { unspentOutput in
            Output(value: unspentOutput.value,
                   lockingScript: unspentOutput.lockingScript,
                   tokenData: unspentOutput.tokenData)
        }

        for (index, unspentOutput) in builder.orderedUnspentOutputs.enumerated() {
            guard let privateKey = builder.findPrivateKey(for: unspentOutput) else { throw Error.cannotCreateTransaction }
            let unlocker = builder.makeUnlocker(for: unspentOutput)
            transaction = try transaction.signInputInPlace(
                at: index,
                spending: unspentOutput,
                privateKey: privateKey,
                signatureFormat: builder.signatureFormat,
                unlocker: unlocker,
                using: unsignedTransaction,
                spentOutputs: spentOutputs
            )
        }

        return transaction
    }
}
