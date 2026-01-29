// Account+TokenGenesis.swift

import Foundation

extension Account {
    public struct TokenGenesis: Sendable {
        public struct Recipient: Sendable {
            public let address: Address
            public let bchAmount: Satoshi?
            public let fungibleAmount: UInt64?
            public let nft: CashTokens.NFT?
            
            public init(address: Address,
                        bchAmount: Satoshi? = nil,
                        fungibleAmount: UInt64? = nil,
                        nft: CashTokens.NFT? = nil) throws {
                try TokenGenesisValidation.validateFungibleAmount(fungibleAmount)
                try TokenGenesisValidation.validateCommitment(nft)
                self.address = address
                self.bchAmount = bchAmount
                self.fungibleAmount = fungibleAmount
                self.nft = nft
            }
        }
        
        public let recipients: [Recipient]
        public let reservedSupplyToSelf: ReservedSupply?
        public let feeOverride: Wallet.FeePolicy.Override?
        public let feeContext: Wallet.FeePolicy.RecommendationContext
        public let shouldAllowDustDonation: Bool
        
        public init(recipients: [Recipient],
                    reservedSupplyToSelf: ReservedSupply? = nil,
                    feeOverride: Wallet.FeePolicy.Override? = nil,
                    feeContext: Wallet.FeePolicy.RecommendationContext = .init(),
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
    
    public struct ReservedSupply: Sendable {
        public let fungibleAmount: UInt64
        public let includeMintingNFT: Bool
        public let commitment: Data
        
        public init(fungibleAmount: UInt64,
                    includeMintingNFT: Bool,
                    commitment: Data = .init()) throws {
            try TokenGenesisValidation.validateFungibleAmount(fungibleAmount)
            try TokenGenesisValidation.validateCommitment(commitment)
            self.fungibleAmount = fungibleAmount
            self.includeMintingNFT = includeMintingNFT
            self.commitment = commitment
        }
    }
}

private enum TokenGenesisValidation {
    static func validateRecipients(_ recipients: [Account.TokenGenesis.Recipient]) throws {
        for recipient in recipients {
            try validateFungibleAmount(recipient.fungibleAmount)
            try validateCommitment(recipient.nft)
        }
    }
    
    static func validateReservedSupply(_ reservedSupply: Account.ReservedSupply) throws {
        try validateFungibleAmount(reservedSupply.fungibleAmount)
        try validateCommitment(reservedSupply.commitment)
    }
    
    static func validateFungibleAmount(_ amount: UInt64?) throws {
        if let amount, amount == 0 {
            throw Account.Error.tokenGenesisFungibleAmountIsZero
        }
    }
    
    static func validateFungibleAmount(_ amount: UInt64) throws {
        if amount == 0 {
            throw Account.Error.tokenGenesisFungibleAmountIsZero
        }
    }
    
    static func validateCommitment(_ nonFungibleToken: CashTokens.NFT?) throws {
        if let nonFungibleToken {
            try validateCommitment(nonFungibleToken.commitment)
        }
    }
    
    static func validateCommitment(_ commitment: Data) throws {
        try TokenOperationValidation.validateCommitmentLength(commitment) { maximum, actual in
            Account.Error.tokenGenesisNonFungibleTokenCommitmentTooLong(
                maximum: maximum,
                actual: actual
            )
        }
    }
}
