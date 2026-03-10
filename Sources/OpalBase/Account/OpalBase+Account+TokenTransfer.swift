// OpalBase+Account+TokenTransfer.swift

import Foundation

extension _OpalBase.Account {
    public struct TokenTransfer: Sendable {
        public struct Recipient: Sendable {
            public let address: OpalBase.Address
            public let amount: OpalBase.Satoshi
            public let tokenData: OpalBase.CashTokens.TokenData
            
            public init(address: OpalBase.Address, amount: OpalBase.Satoshi, tokenData: OpalBase.CashTokens.TokenData) {
                self.address = address
                self.amount = amount
                self.tokenData = tokenData
            }
        }
        
        public struct Burn: Sendable {
            public let tokenData: OpalBase.CashTokens.TokenData
            
            public init(tokenData: OpalBase.CashTokens.TokenData) {
                self.tokenData = tokenData
            }
        }
        
        public let recipients: [Recipient]
        public let burns: [Burn]
        public let feeOverride: OpalBase.Wallet.FeePolicy.Override?
        public let feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext
        public let shouldAllowDustDonation: Bool
        
        public init(recipients: [Recipient],
                    burns: [Burn] = .init(),
                    feeOverride: OpalBase.Wallet.FeePolicy.Override? = nil,
                    feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext = .init(),
                    shouldAllowDustDonation: Bool = false) {
            self.recipients = recipients
            self.burns = burns
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.shouldAllowDustDonation = shouldAllowDustDonation
        }
    }
}
