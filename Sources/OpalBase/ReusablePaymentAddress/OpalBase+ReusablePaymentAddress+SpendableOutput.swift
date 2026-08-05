// OpalBase+ReusablePaymentAddress+SpendableOutput.swift

extension _OpalBase.ReusablePaymentAddress {
    /// A matched output whose current exact unspent payload has been verified.
    public struct SpendableOutput: Sendable {
        public let unspentOutput: OpalBase.Transaction.Output.Unspent
        public let receivingPublicKey: OpalBase.Key.PublicKey

        let capability: ReceivingCapability

        init(
            unspentOutput: OpalBase.Transaction.Output.Unspent,
            capability: ReceivingCapability
        ) {
            self.unspentOutput = unspentOutput
            self.receivingPublicKey = capability.publicKey
            self.capability = capability
        }
    }
}
