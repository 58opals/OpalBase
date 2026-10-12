// TokenGenesisValidation.swift

import Foundation

enum TokenGenesisValidation {
    static func validateRecipients(_ recipients: [OpalBase.Account.TokenGenesis.Recipient]) throws {
        for recipient in recipients {
            try validateRecipientPayload(fungibleAmount: recipient.fungibleAmount, nft: recipient.nft)
        }
    }

    static func validateReservedSupply(_ reservedSupply: OpalBase.Account.ReservedSupply) throws {
        try validateFungibleAmount(reservedSupply.fungibleAmount)
        try validateCommitment(reservedSupply.commitment)
    }

    static func validateFungibleSupply(
        recipients: [OpalBase.Account.TokenGenesis.Recipient],
        reservedSupply: OpalBase.Account.ReservedSupply?
    ) throws {
        let recipientSupply = try recipients.reduce(UInt64(0)) { total, recipient in
            try total.addOrThrow(recipient.fungibleAmount ?? 0,
                                 overflowError: OpalBase.Account.Error.paymentExceedsMaximumAmount)
        }
        let totalSupply = try recipientSupply.addOrThrow(
            reservedSupply?.fungibleAmount ?? 0,
            overflowError: OpalBase.Account.Error.paymentExceedsMaximumAmount
        )
        guard totalSupply <= OpalBase.CashTokens.TokenData.maximumFungibleAmount else {
            throw OpalBase.Account.Error.paymentExceedsMaximumAmount
        }
    }

    static func validateRecipientPayload(fungibleAmount: UInt64?, nft: OpalBase.CashTokens.NFT?) throws {
        try validateTokenData(fungibleAmount: fungibleAmount, nft: nft)
        try validateFungibleAmount(fungibleAmount)
        try validateCommitment(nft)
    }

    static func validateTokenData(fungibleAmount: UInt64?, nft: OpalBase.CashTokens.NFT?) throws {
        guard fungibleAmount != nil || nft != nil else {
            throw OpalBase.Account.Error.tokenGenesisRecipientHasNoTokenData
        }
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
