// AccountActor+TokenTransferModel.swift

import Foundation

extension AccountActor {
    public struct TokenTransferModel: Sendable {
        public struct Recipient: Sendable {
            public let address: AddressModel
            public let amount: SatoshiModel
            public let tokenData: CashTokensModel.TokenData
            
            public init(address: AddressModel, amount: SatoshiModel, tokenData: CashTokensModel.TokenData) {
                self.address = address
                self.amount = amount
                self.tokenData = tokenData
            }
        }
        
        public struct Burn: Sendable {
            public let tokenData: CashTokensModel.TokenData
            
            public init(tokenData: CashTokensModel.TokenData) {
                self.tokenData = tokenData
            }
        }
        
        public let recipients: [Recipient]
        public let burns: [Burn]
        public let feeOverride: WalletActor.FeePolicy.Override?
        public let feeContext: WalletActor.FeePolicy.RecommendationContext
        public let shouldAllowDustDonation: Bool
        
        public init(recipients: [Recipient],
                    burns: [Burn] = .init(),
                    feeOverride: WalletActor.FeePolicy.Override? = nil,
                    feeContext: WalletActor.FeePolicy.RecommendationContext = .init(),
                    shouldAllowDustDonation: Bool = false) {
            self.recipients = recipients
            self.burns = burns
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.shouldAllowDustDonation = shouldAllowDustDonation
        }
    }
}
