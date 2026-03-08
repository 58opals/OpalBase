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
                try TokenGenesisValidationModel.validateFungibleAmount(fungibleAmount)
                try TokenGenesisValidationModel.validateCommitment(nft)
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
            try TokenGenesisValidationModel.validateRecipients(recipients)
            if let reservedSupplyToSelf {
                try TokenGenesisValidationModel.validateReservedSupply(reservedSupplyToSelf)
            }
            self.recipients = recipients
            self.reservedSupplyToSelf = reservedSupplyToSelf
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.shouldAllowDustDonation = shouldAllowDustDonation
        }
    }
}

private enum TokenGenesisValidationModel {
    static func validateRecipients(_ recipients: [OpalBase.Account.TokenGenesis.Recipient]) throws {
        for recipient in recipients {
            try validateFungibleAmount(recipient.fungibleAmount)
            try validateCommitment(recipient.nft)
        }
    }
    
    static func validateReservedSupply(_ reservedSupply: OpalBase.Account.ReservedSupply) throws {
        try validateFungibleAmount(reservedSupply.fungibleAmount)
        try validateCommitment(reservedSupply.commitment)
    }
    
    static func validateFungibleAmount(_ amount: UInt64?) throws {
        try TokenOperationValidator.requireNonZeroFungibleAmount(amount) {
            OpalBase.Account.Error.tokenGenesisFungibleAmountIsZero
        }
    }
    
    static func validateFungibleAmount(_ amount: UInt64) throws {
        try TokenOperationValidator.requireNonZeroFungibleAmount(amount) {
            OpalBase.Account.Error.tokenGenesisFungibleAmountIsZero
        }
    }
    
    static func validateCommitment(_ nonFungibleToken: OpalBase.CashTokens.NFT?) throws {
        if let nonFungibleToken {
            try validateCommitment(nonFungibleToken.commitment)
        }
    }
    
    static func validateCommitment(_ commitment: Data) throws {
        try TokenOperationValidator.validateCommitmentLength(commitment) { maximum, actual in
            OpalBase.Account.Error.tokenGenesisNonFungibleTokenCommitmentTooLong(
                maximum: maximum,
                actual: actual
            )
        }
    }
}
