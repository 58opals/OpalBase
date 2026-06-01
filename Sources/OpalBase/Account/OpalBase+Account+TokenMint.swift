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
