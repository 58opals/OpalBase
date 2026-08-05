// OpalBase+ReusablePaymentAddress+MempoolMatch.swift

extension _OpalBase.ReusablePaymentAddress {
    /// A verified Cash Code output in the backend's current mempool snapshot.
    public struct MempoolMatch: Codable, Hashable, Sendable {
        public let fee: UInt64
        public let hasUnconfirmedParent: Bool
        public let output: MatchedOutput
        public let derivation: DerivationContext

        init(
            reference: MempoolTransactionReference,
            match: Match
        ) {
            self.fee = reference.fee
            self.hasUnconfirmedParent = reference.hasUnconfirmedParent
            self.output = MatchedOutput(match: match)
            self.derivation = DerivationContext(match: match)
        }
    }
}
