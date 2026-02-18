// Account+TokenTransfer.swift

import Foundation

extension Account {
    public struct TokenTransfer: Sendable {
        public struct Recipient: Sendable {
            public let address: Address
            public let amount: Satoshi
            public let tokenData: CashTokens.TokenData
            
            public init(address: Address, amount: Satoshi, tokenData: CashTokens.TokenData) {
                self.address = address
                self.amount = amount
                self.tokenData = tokenData
            }
        }
        
        public struct Burn: Sendable {
            public let tokenData: CashTokens.TokenData
            
            public init(tokenData: CashTokens.TokenData) {
                self.tokenData = tokenData
            }
        }
        
        public let recipients: [Recipient]
        public let burns: [Burn]
        public let feeOverride: Wallet.FeePolicy.Override?
        public let feeContext: Wallet.FeePolicy.RecommendationContext
        public let shouldAllowDustDonation: Bool
        
        public init(recipients: [Recipient],
                    burns: [Burn] = .init(),
                    feeOverride: Wallet.FeePolicy.Override? = nil,
                    feeContext: Wallet.FeePolicy.RecommendationContext = .init(),
                    shouldAllowDustDonation: Bool = false) {
            self.recipients = recipients
            self.burns = burns
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.shouldAllowDustDonation = shouldAllowDustDonation
        }
    }
}
