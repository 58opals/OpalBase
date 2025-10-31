// Account+Payment.swift

import Foundation

extension Account {
    public struct Payment: Sendable {
        public struct Recipient: Sendable {
            public let address: Address
            public let amount: Satoshi
            
            public init(address: Address, amount: Satoshi) {
                self.address = address
                self.amount = amount
            }
        }
        
        public let recipients: [Recipient]
        public let feeOverride: Wallet.FeePolicy.Override?
        public let feeContext: Wallet.FeePolicy.RecommendationContext
        public let coinSelection: Address.Book.CoinSelection
        public let allowDustDonation: Bool
        
        public init(recipients: [Recipient],
                    feeOverride: Wallet.FeePolicy.Override? = nil,
                    feeContext: Wallet.FeePolicy.RecommendationContext = .init(),
                    coinSelection: Address.Book.CoinSelection = .greedyLargestFirst,
                    allowDustDonation: Bool = false) {
            self.recipients = recipients
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.coinSelection = coinSelection
            self.allowDustDonation = allowDustDonation
        }
    }
}
