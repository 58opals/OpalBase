// Account+TokenMint.swift

import Foundation

extension Account {
    public struct TokenMint: Sendable {
        public struct Recipient: Sendable {
            public let address: Address
            public let bchAmount: Satoshi?
            public let fungibleAmount: UInt64?
            public let nft: CashTokens.NFT?
            
            public init(address: Address,
                        bchAmount: Satoshi? = nil,
                        fungibleAmount: UInt64? = nil,
                        nft: CashTokens.NFT? = nil) throws {
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
            case toAddress(Address, bchAmount: Satoshi? = nil)
            case burn
        }
        
        public let category: CashTokens.CategoryID
        public let recipients: [Recipient]
        public let authorityReturn: AuthorityReturn
        public let feeOverride: Wallet.FeePolicy.Override?
        public let feeContext: Wallet.FeePolicy.RecommendationContext
        public let shouldAllowDustDonation: Bool
        
        public init(category: CashTokens.CategoryID,
                    recipients: [Recipient],
                    authorityReturn: AuthorityReturn = .toWalletChange,
                    feeOverride: Wallet.FeePolicy.Override? = nil,
                    feeContext: Wallet.FeePolicy.RecommendationContext = .init(),
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
    static func validateRequest(recipients: [Account.TokenMint.Recipient],
                                authorityReturn: Account.TokenMint.AuthorityReturn) throws {
        if recipients.isEmpty {
            switch authorityReturn {
            case .toWalletChange:
                throw Account.Error.tokenMintHasNoRecipientsAndAuthorityReturnToWalletChange
            case .toAddress, .burn:
                break
            }
        }
    }
    
    static func validateRecipients(_ recipients: [Account.TokenMint.Recipient]) throws {
        let nonTokenAwareAddresses = recipients
            .map(\.address)
            .filter { !$0.supportsTokens }
        if !nonTokenAwareAddresses.isEmpty {
            throw Account.Error.tokenMintRequiresTokenAwareAddress(nonTokenAwareAddresses)
        }
    }
    
    static func validateAuthorityReturn(_ authorityReturn: Account.TokenMint.AuthorityReturn) throws {
        switch authorityReturn {
        case .toAddress(let address, _):
            try TokenOperationValidation.requireTokenAwareAddress(address) { offending in
                Account.Error.tokenMintRequiresTokenAwareAddress(offending)
            }
        case .toWalletChange, .burn:
            break
        }
    }
    
    static func validateTokenData(fungibleAmount: UInt64?, nft: CashTokens.NFT?) throws {
        guard fungibleAmount != nil || nft != nil else {
            throw Account.Error.tokenMintRecipientHasNoTokenData
        }
    }
    
    static func validateFungibleAmount(_ fungibleAmount: UInt64?) throws {
        if let fungibleAmount, fungibleAmount == 0 {
            throw Account.Error.tokenMintFungibleAmountIsZero
        }
    }
    
    static func validateCommitment(_ nonFungibleToken: CashTokens.NFT?) throws {
        if let nonFungibleToken {
            try validateCommitment(nonFungibleToken.commitment)
        }
    }
    
    static func validateCommitment(_ commitment: Data) throws {
        try TokenOperationValidation.validateCommitmentLength(commitment) { maximum, actual in
            Account.Error.tokenMintNonFungibleTokenCommitmentTooLong(
                maximum: maximum,
                actual: actual
            )
        }
    }
}
