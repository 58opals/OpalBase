// OpalBase+Account+Payment.swift

import Foundation

extension _OpalBase.Account {
    /// A BCH payment request used to prepare a wallet-owned spend.
    public struct Payment: Sendable {
        /// A recipient output in a BCH payment.
        public struct Recipient: Sendable {
            public let address: OpalBase.Address
            public let amount: OpalBase.Satoshi
            public let tokenData: OpalBase.CashTokens.TokenData?
            
            public init(address: OpalBase.Address, amount: OpalBase.Satoshi, tokenData: OpalBase.CashTokens.TokenData? = nil) {
                self.address = address
                self.amount = amount
                self.tokenData = tokenData
            }
        }
        
        public let recipients: [Recipient]
        public let feeOverride: OpalBase.Wallet.FeePolicy.Override?
        public let feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext
        public let coinSelection: CoinSelectionStrategy
        public let tokenInputPolicy: TokenInputPolicy
        public let shouldAllowDustDonation: Bool
        public let shouldAllowUnsafeTokenTransfers: Bool
        
        public init(recipients: [Recipient],
                    feeOverride: OpalBase.Wallet.FeePolicy.Override? = nil,
                    feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext = .init(),
                    coinSelection: CoinSelectionStrategy = .greedyLargestFirst,
                    tokenInputPolicy: TokenInputPolicy = .excludeTokenUTXOs,
                    shouldAllowDustDonation: Bool = false,
                    shouldAllowUnsafeTokenTransfers: Bool = false) {
            self.recipients = recipients
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.coinSelection = coinSelection
            self.tokenInputPolicy = tokenInputPolicy
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.shouldAllowUnsafeTokenTransfers = shouldAllowUnsafeTokenTransfers
        }
    }
}
