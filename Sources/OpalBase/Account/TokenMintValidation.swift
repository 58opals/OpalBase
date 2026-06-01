// TokenMintValidation.swift

import Foundation

enum TokenMintValidation {
    static func validateRequest(recipients: [OpalBase.Account.TokenMint.Recipient],
                                authorityReturn: OpalBase.Account.TokenMint.AuthorityReturn) throws {
        guard recipients.isEmpty else { return }

        switch authorityReturn {
        case .toWalletChange:
            throw OpalBase.Account.Error.tokenMintHasNoRecipientsAndAuthorityReturnToWalletChange
        case .toAddress, .burn:
            break
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
