// OpalBase+ReusablePaymentAddress+ConfirmedMatch.swift

extension _OpalBase.ReusablePaymentAddress {
    /// A verified Cash Code output found in confirmed block history.
    public struct ConfirmedMatch: Codable, Hashable, Sendable {
        public let blockHeight: UInt
        public let output: MatchedOutput
        public let derivation: DerivationContext

        init(
            blockHeight: UInt,
            match: Match
        ) {
            self.blockHeight = blockHeight
            self.output = MatchedOutput(match: match)
            self.derivation = DerivationContext(match: match)
        }
    }
}
