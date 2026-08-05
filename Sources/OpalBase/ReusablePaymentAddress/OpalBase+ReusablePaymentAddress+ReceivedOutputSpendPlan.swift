// OpalBase+ReusablePaymentAddress+ReceivedOutputSpendPlan.swift

extension _OpalBase.ReusablePaymentAddress {
    /// A locally buildable spend of independently verified Cash Code UTXOs.
    ///
    /// Token-bearing inputs require an exact one-for-one token payload in the
    /// requested outputs. More general token transformations remain in the
    /// account token-authoring APIs.
    public struct ReceivedOutputSpendPlan: Sendable {
        public let inputs: [OpalBase.Transaction.Output.Unspent]
        public let recipientOutputs: [OpalBase.Transaction.Output]
        public let changeOutput: OpalBase.Transaction.Output
        public let feeRate: UInt64
        public let shouldAllowDustDonation: Bool

        private let signingKeys: [
            OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey
        ]

        init(
            spendableOutputs: [SpendableOutput],
            recipientOutputs: [OpalBase.Transaction.Output],
            changeOutput: OpalBase.Transaction.Output,
            feeRate: UInt64,
            shouldAllowDustDonation: Bool
        ) throws {
            guard !spendableOutputs.isEmpty,
                  !recipientOutputs.isEmpty
            else {
                throw Error.matchedOutputNotFound
            }
            let inputs = spendableOutputs.map(\.unspentOutput)
            guard Set(inputs.map(OpalBase.Transaction.Outpoint.init)).count
                == inputs.count
            else {
                throw Error.invalidPersistentState
            }
            try Self.requireCashTokenPreservation(
                inputs: inputs,
                outputs: recipientOutputs + [changeOutput]
            )
            self.inputs = inputs
            self.recipientOutputs = recipientOutputs
            self.changeOutput = changeOutput
            self.feeRate = feeRate
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.signingKeys = Dictionary(
                uniqueKeysWithValues: spendableOutputs.map {
                    ($0.unspentOutput, $0.capability.signingKey)
                }
            )
        }

        /// Builds and signs one transaction without exporting receiving keys.
        public func buildTransaction() throws -> OpalBase.Transaction {
            try OpalBase.Transaction.build(
                utxoSigningKeyPairs: signingKeys,
                recipientOutputs: recipientOutputs,
                changeOutput: changeOutput,
                outputOrderingStrategy: .canonicalBIP69,
                signatureFormat: .schnorr,
                feePerByte: feeRate,
                shouldAllowDustDonation: shouldAllowDustDonation
            )
        }

        private static func requireCashTokenPreservation(
            inputs: [OpalBase.Transaction.Output.Unspent],
            outputs: [OpalBase.Transaction.Output]
        ) throws {
            var remainingOutputTokens = outputs.compactMap(\.tokenData)
            for inputToken in inputs.compactMap(\.tokenData) {
                guard let index = remainingOutputTokens.firstIndex(
                    of: inputToken
                ) else {
                    throw Error.cashTokenPreservationRequired
                }
                remainingOutputTokens.remove(at: index)
            }
            guard remainingOutputTokens.isEmpty else {
                throw Error.cashTokenPreservationRequired
            }
        }
    }
}
