// OpalBase+Account+TokenGenesis.swift

import Foundation

extension _OpalBase.Account {
    public struct TokenGenesis: Sendable {
        public struct Recipient: Sendable {
            public let address: OpalBase.Address
            public let bchAmount: OpalBase.Satoshi?
            public let fungibleAmount: UInt64?
            public let nft: OpalBase.CashTokens.NFT?
            
            public init(address: OpalBase.Address,
                        bchAmount: OpalBase.Satoshi? = nil,
                        fungibleAmount: UInt64? = nil,
                        nft: OpalBase.CashTokens.NFT? = nil) throws {
                try TokenGenesisValidation.validateRecipientPayload(fungibleAmount: fungibleAmount, nft: nft)
                self.address = address
                self.bchAmount = bchAmount
                self.fungibleAmount = fungibleAmount
                self.nft = nft
            }
        }
        
        public let recipients: [Recipient]
        public let reservedSupplyToSelf: ReservedSupply?
        public let feeOverride: OpalBase.Wallet.FeePolicy.Override?
        public let feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext
        public let shouldAllowDustDonation: Bool
        
        public init(recipients: [Recipient],
                    reservedSupplyToSelf: ReservedSupply? = nil,
                    feeOverride: OpalBase.Wallet.FeePolicy.Override? = nil,
                    feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext = .init(),
                    shouldAllowDustDonation: Bool = false) throws {
            try TokenGenesisValidation.validateRecipients(recipients)
            if let reservedSupplyToSelf {
                try TokenGenesisValidation.validateReservedSupply(reservedSupplyToSelf)
            }
            self.recipients = recipients
            self.reservedSupplyToSelf = reservedSupplyToSelf
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.shouldAllowDustDonation = shouldAllowDustDonation
        }
    }
}
