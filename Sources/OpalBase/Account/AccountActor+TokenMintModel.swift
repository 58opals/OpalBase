// AccountActor+TokenMintModel.swift

import Foundation

extension AccountActor {
    public struct TokenMintModel: Sendable {
        public struct Recipient: Sendable {
            public let address: AddressModel
            public let bchAmount: SatoshiModel?
            public let fungibleAmount: UInt64?
            public let nft: CashTokensModel.NFTModel?
            
            public init(address: AddressModel,
                        bchAmount: SatoshiModel? = nil,
                        fungibleAmount: UInt64? = nil,
                        nft: CashTokensModel.NFTModel? = nil) throws {
                try TokenMintValidationModel.validateTokenData(fungibleAmount: fungibleAmount, nft: nft)
                try TokenMintValidationModel.validateFungibleAmount(fungibleAmount)
                try TokenMintValidationModel.validateCommitment(nft)
                self.address = address
                self.bchAmount = bchAmount
                self.fungibleAmount = fungibleAmount
                self.nft = nft
            }
        }
        
        public enum AuthorityReturn: Sendable {
            case toWalletChange
            case toAddress(AddressModel, bchAmount: SatoshiModel? = nil)
            case burn
        }
        
        public let category: CashTokensModel.CategoryIDModel
        public let recipients: [Recipient]
        public let authorityReturn: AuthorityReturn
        public let feeOverride: WalletActor.FeePolicy.Override?
        public let feeContext: WalletActor.FeePolicy.RecommendationContext
        public let shouldAllowDustDonation: Bool
        
        public init(category: CashTokensModel.CategoryIDModel,
                    recipients: [Recipient],
                    authorityReturn: AuthorityReturn = .toWalletChange,
                    feeOverride: WalletActor.FeePolicy.Override? = nil,
                    feeContext: WalletActor.FeePolicy.RecommendationContext = .init(),
                    shouldAllowDustDonation: Bool = false) throws {
            try TokenMintValidationModel.validateRequest(recipients: recipients, authorityReturn: authorityReturn)
            try TokenMintValidationModel.validateRecipients(recipients)
            try TokenMintValidationModel.validateAuthorityReturn(authorityReturn)
            self.category = category
            self.recipients = recipients
            self.authorityReturn = authorityReturn
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.shouldAllowDustDonation = shouldAllowDustDonation
        }
    }
}

private enum TokenMintValidationModel {
    static func validateRequest(recipients: [AccountActor.TokenMintModel.Recipient],
                                authorityReturn: AccountActor.TokenMintModel.AuthorityReturn) throws {
        if recipients.isEmpty {
            switch authorityReturn {
            case .toWalletChange:
                throw AccountActor.Error.tokenMintHasNoRecipientsAndAuthorityReturnToWalletChange
            case .toAddress, .burn:
                break
            }
        }
    }
    
    static func validateRecipients(_ recipients: [AccountActor.TokenMintModel.Recipient]) throws {
        try TokenOperationValidator.requireTokenAwareAddresses(recipients.map(\.address)) { offending in
            AccountActor.Error.tokenMintRequiresTokenAwareAddress(offending)
        }
    }
    
    static func validateAuthorityReturn(_ authorityReturn: AccountActor.TokenMintModel.AuthorityReturn) throws {
        switch authorityReturn {
        case .toAddress(let address, _):
            try TokenOperationValidator.requireTokenAwareAddress(address) { offending in
                AccountActor.Error.tokenMintRequiresTokenAwareAddress(offending)
            }
        case .toWalletChange, .burn:
            break
        }
    }
    
    static func validateTokenData(fungibleAmount: UInt64?, nft: CashTokensModel.NFTModel?) throws {
        guard fungibleAmount != nil || nft != nil else {
            throw AccountActor.Error.tokenMintRecipientHasNoTokenData
        }
    }
    
    static func validateFungibleAmount(_ fungibleAmount: UInt64?) throws {
        try TokenOperationValidator.requireNonZeroFungibleAmount(fungibleAmount) {
            AccountActor.Error.tokenMintFungibleAmountIsZero
        }
    }
    
    static func validateCommitment(_ nonFungibleToken: CashTokensModel.NFTModel?) throws {
        if let nonFungibleToken {
            try validateCommitment(nonFungibleToken.commitment)
        }
    }
    
    static func validateCommitment(_ commitment: Data) throws {
        try TokenOperationValidator.validateCommitmentLength(commitment) { maximum, actual in
            AccountActor.Error.tokenMintNonFungibleTokenCommitmentTooLong(
                maximum: maximum,
                actual: actual
            )
        }
    }
}
