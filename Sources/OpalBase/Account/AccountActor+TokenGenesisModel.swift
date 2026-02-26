// AccountActor+TokenGenesisModel.swift

import Foundation

extension AccountActor {
    public struct TokenGenesisModel: Sendable {
        public struct Recipient: Sendable {
            public let address: AddressModel
            public let bchAmount: SatoshiModel?
            public let fungibleAmount: UInt64?
            public let nft: CashTokensModel.NFTModel?
            
            public init(address: AddressModel,
                        bchAmount: SatoshiModel? = nil,
                        fungibleAmount: UInt64? = nil,
                        nft: CashTokensModel.NFTModel? = nil) throws {
                try TokenGenesisValidationModel.validateFungibleAmount(fungibleAmount)
                try TokenGenesisValidationModel.validateCommitment(nft)
                self.address = address
                self.bchAmount = bchAmount
                self.fungibleAmount = fungibleAmount
                self.nft = nft
            }
        }
        
        public let recipients: [Recipient]
        public let reservedSupplyToSelf: ReservedSupplyModel?
        public let feeOverride: WalletActor.FeePolicy.Override?
        public let feeContext: WalletActor.FeePolicy.RecommendationContext
        public let shouldAllowDustDonation: Bool
        
        public init(recipients: [Recipient],
                    reservedSupplyToSelf: ReservedSupplyModel? = nil,
                    feeOverride: WalletActor.FeePolicy.Override? = nil,
                    feeContext: WalletActor.FeePolicy.RecommendationContext = .init(),
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
    
    public struct ReservedSupplyModel: Sendable {
        public let fungibleAmount: UInt64
        public let shouldIncludeMintingNonFungibleToken: Bool
        public let commitment: Data
        
        public init(fungibleAmount: UInt64,
                    shouldIncludeMintingNonFungibleToken: Bool,
                    commitment: Data = .init()) throws {
            try TokenGenesisValidationModel.validateFungibleAmount(fungibleAmount)
            try TokenGenesisValidationModel.validateCommitment(commitment)
            self.fungibleAmount = fungibleAmount
            self.shouldIncludeMintingNonFungibleToken = shouldIncludeMintingNonFungibleToken
            self.commitment = commitment
        }
    }
}

private enum TokenGenesisValidationModel {
    static func validateRecipients(_ recipients: [AccountActor.TokenGenesisModel.Recipient]) throws {
        for recipient in recipients {
            try validateFungibleAmount(recipient.fungibleAmount)
            try validateCommitment(recipient.nft)
        }
    }
    
    static func validateReservedSupply(_ reservedSupply: AccountActor.ReservedSupplyModel) throws {
        try validateFungibleAmount(reservedSupply.fungibleAmount)
        try validateCommitment(reservedSupply.commitment)
    }
    
    static func validateFungibleAmount(_ amount: UInt64?) throws {
        try TokenOperationValidator.requireNonZeroFungibleAmount(amount) {
            AccountActor.Error.tokenGenesisFungibleAmountIsZero
        }
    }
    
    static func validateFungibleAmount(_ amount: UInt64) throws {
        try TokenOperationValidator.requireNonZeroFungibleAmount(amount) {
            AccountActor.Error.tokenGenesisFungibleAmountIsZero
        }
    }
    
    static func validateCommitment(_ nonFungibleToken: CashTokensModel.NFTModel?) throws {
        if let nonFungibleToken {
            try validateCommitment(nonFungibleToken.commitment)
        }
    }
    
    static func validateCommitment(_ commitment: Data) throws {
        try TokenOperationValidator.validateCommitmentLength(commitment) { maximum, actual in
            AccountActor.Error.tokenGenesisNonFungibleTokenCommitmentTooLong(
                maximum: maximum,
                actual: actual
            )
        }
    }
}
