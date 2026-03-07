// OpalBase+Account+Payment.swift

import Foundation

extension _OpalBase.Account {
    public struct Payment: Sendable {
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
        public let coinSelection: OpalBase.Address.Book.CoinSelectionModel
        public let tokenSelectionPolicy: OpalBase.Address.Book.CoinSelectionModel.TokenSelectionPolicy
        public let shouldAllowDustDonation: Bool
        public let shouldAllowUnsafeTokenTransfers: Bool
        
        public init(recipients: [Recipient],
                    feeOverride: OpalBase.Wallet.FeePolicy.Override? = nil,
                    feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext = .init(),
                    coinSelection: OpalBase.Address.Book.CoinSelectionModel = .greedyLargestFirst,
                    tokenSelectionPolicy: OpalBase.Address.Book.CoinSelectionModel.TokenSelectionPolicy = .excludeTokenUTXOs,
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
