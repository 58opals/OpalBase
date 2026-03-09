// OpalBase+Account+TokenMint.swift

import Foundation

extension _OpalBase.Account {
    public struct TokenMint: Sendable {
        public struct Recipient: Sendable {
            public let address: OpalBase.Address
            public let bchAmount: OpalBase.Satoshi?
            public let fungibleAmount: UInt64?
            public let nft: OpalBase.CashTokens.NFT?
            
            public init(address: OpalBase.Address,
                        bchAmount: OpalBase.Satoshi? = nil,
                        fungibleAmount: UInt64? = nil,
                        nft: OpalBase.CashTokens.NFT? = nil) throws {
                try TokenMintValidation.validateTokenData(fungibleAmount: fungibleAmount, nft: nft)
                try TokenMintValidation.validateFungibleAmount(fungibleAmount)
                try TokenMintValidation.validateCommitment(nft)
                self.address = address
                self.bchAmount = bchAmount
                self.fungibleAmount = fungibleAmount
                self.nft = nft
            }
        }
        
        public enum AuthorityReturn: Sendable {
            case toWalletChange
            case toAddress(OpalBase.Address, bchAmount: OpalBase.Satoshi? = nil)
            case burn
        }
        
        public let category: OpalBase.CashTokens.CategoryID
        public let recipients: [Recipient]
        public let authorityReturn: AuthorityReturn
        public let feeOverride: OpalBase.Wallet.FeePolicy.Override?
        public let feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext
        public let shouldAllowDustDonation: Bool
        
        public init(category: OpalBase.CashTokens.CategoryID,
                    recipients: [Recipient],
                    authorityReturn: AuthorityReturn = .toWalletChange,
                    feeOverride: OpalBase.Wallet.FeePolicy.Override? = nil,
                    feeContext: OpalBase.Wallet.FeePolicy.RecommendationContext = .init(),
                    shouldAllowDustDonation: Bool = false) throws {
            try TokenMintValidation.validateRequest(recipients: recipients, authorityReturn: authorityReturn)
            try TokenMintValidation.validateRecipients(recipients)
            try TokenMintValidation.validateAuthorityReturn(authorityReturn)
            self.category = category
            self.recipients = recipients
            self.authorityReturn = authorityReturn
            self.feeOverride = feeOverride
            self.feeContext = feeContext
            self.shouldAllowDustDonation = shouldAllowDustDonation
        }
    }
}

private enum TokenMintValidation {
    static func validateRequest(recipients: [OpalBase.Account.TokenMint.Recipient],
                                authorityReturn: OpalBase.Account.TokenMint.AuthorityReturn) throws {
        if recipients.isEmpty {
            switch authorityReturn {
            case .toWalletChange:
                throw OpalBase.Account.Error.tokenMintHasNoRecipientsAndAuthorityReturnToWalletChange
            case .toAddress, .burn:
                break
            }
        }
    }
    
    static func validateRecipients(_ recipients: [OpalBase.Account.TokenMint.Recipient]) throws {
        try TokenOperationValidator.requireTokenAwareAddresses(recipients.map(\.address)) { offending in
            OpalBase.Account.Error.tokenMintRequiresTokenAwareAddress(offending)
        }
    }
    
    static func validateAuthorityReturn(_ authorityReturn: OpalBase.Account.TokenMint.AuthorityReturn) throws {
        switch authorityReturn {
        case .toAddress(let address, _):
            try TokenOperationValidator.requireTokenAwareAddress(address) { offending in
                OpalBase.Account.Error.tokenMintRequiresTokenAwareAddress(offending)
            }
        case .toWalletChange, .burn:
            break
        }
    }
    
    static func validateTokenData(fungibleAmount: UInt64?, nft: OpalBase.CashTokens.NFT?) throws {
        guard fungibleAmount != nil || nft != nil else {
            throw OpalBase.Account.Error.tokenMintRecipientHasNoTokenData
        }
    }
    
    static func validateFungibleAmount(_ fungibleAmount: UInt64?) throws {
        try TokenOperationValidator.requireNonZeroFungibleAmount(fungibleAmount) {
            OpalBase.Account.Error.tokenMintFungibleAmountIsZero
        }
    }
    
    static func validateCommitment(_ nonFungibleToken: OpalBase.CashTokens.NFT?) throws {
        if let nonFungibleToken {
            try validateCommitment(nonFungibleToken.commitment)
        }
    }
    
    static func validateCommitment(_ commitment: Data) throws {
        try TokenOperationValidator.validateCommitmentLength(commitment) { maximum, actual in
            OpalBase.Account.Error.tokenMintNonFungibleTokenCommitmentTooLong(
                maximum: maximum,
                actual: actual
            )
        }
    }
}
