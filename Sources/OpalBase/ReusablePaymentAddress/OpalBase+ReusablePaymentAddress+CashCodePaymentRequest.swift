// OpalBase+ReusablePaymentAddress+CashCodePaymentRequest.swift

extension _OpalBase.ReusablePaymentAddress {
    /// Exact recipient payload and fee intent for one Cash Code payment.
    public struct CashCodePaymentRequest: Sendable {
        public let amount: OpalBase.Satoshi
        public let tokenData: OpalBase.CashTokens.TokenData?
        public let feeOverride: OpalBase.Wallet.FeePolicy.Override?
        public let feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext
        public let shouldAllowDustDonation: Bool

        public init(
            amount: OpalBase.Satoshi,
            tokenData: OpalBase.CashTokens.TokenData? = nil,
            feeOverride: OpalBase.Wallet.FeePolicy.Override? = nil,
            feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext = .init(),
            shouldAllowDustDonation: Bool = false
        ) {
            self.amount = amount
            self.tokenData = tokenData
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.shouldAllowDustDonation = shouldAllowDustDonation
        }
    }
}
