// Account+Payment.swift

import Foundation

extension Account {
    public struct Payment: Sendable {
        public struct Recipient: Sendable {
            public let address: Address
            public let amount: Satoshi
            public let tokenData: CashTokens.TokenData?
            
            public init(address: Address, amount: Satoshi, tokenData: CashTokens.TokenData? = nil) {
                self.address = address
                self.amount = amount
                self.tokenData = tokenData
            }
        }
        
        public let recipients: [Recipient]
        public let feeOverride: Wallet.FeePolicy.Override?
        public let feeContext: Wallet.FeePolicy.RecommendationContext
        public let coinSelection: Address.Book.CoinSelection
        public let tokenSelectionPolicy: Address.Book.CoinSelection.TokenSelectionPolicy
        public let shouldAllowDustDonation: Bool
        public let shouldAllowUnsafeTokenTransfers: Bool
        
        public init(recipients: [Recipient],
                    feeOverride: Wallet.FeePolicy.Override? = nil,
                    feeContext: Wallet.FeePolicy.RecommendationContext = .init(),
                    coinSelection: Address.Book.CoinSelection = .greedyLargestFirst,
                    tokenSelectionPolicy: Address.Book.CoinSelection.TokenSelectionPolicy = .excludeTokenUTXOs,
                    shouldAllowDustDonation: Bool = false,
                    shouldAllowUnsafeTokenTransfers: Bool = false) {
            self.recipients = recipients
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.coinSelection = coinSelection
            self.tokenSelectionPolicy = tokenSelectionPolicy
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.shouldAllowUnsafeTokenTransfers = shouldAllowUnsafeTokenTransfers
        }
    }
}
