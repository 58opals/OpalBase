// AccountActor+PaymentModel.swift

import Foundation

extension AccountActor {
    public struct PaymentModel: Sendable {
        public struct Recipient: Sendable {
            public let address: AddressModel
            public let amount: SatoshiModel
            public let tokenData: CashTokensModel.TokenData?
            
            public init(address: AddressModel, amount: SatoshiModel, tokenData: CashTokensModel.TokenData? = nil) {
                self.address = address
                self.amount = amount
                self.tokenData = tokenData
            }
        }
        
        public let recipients: [Recipient]
        public let feeOverride: WalletActor.FeePolicy.Override?
        public let feeContext: WalletActor.FeePolicy.RecommendationContext
        public let coinSelection: AddressModel.BookActor.CoinSelectionModel
        public let tokenSelectionPolicy: AddressModel.BookActor.CoinSelectionModel.TokenSelectionPolicy
        public let shouldAllowDustDonation: Bool
        public let shouldAllowUnsafeTokenTransfers: Bool
        
        public init(recipients: [Recipient],
                    feeOverride: WalletActor.FeePolicy.Override? = nil,
                    feeContext: WalletActor.FeePolicy.RecommendationContext = .init(),
                    coinSelection: AddressModel.BookActor.CoinSelectionModel = .greedyLargestFirst,
                    tokenSelectionPolicy: AddressModel.BookActor.CoinSelectionModel.TokenSelectionPolicy = .excludeTokenUTXOs,
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
