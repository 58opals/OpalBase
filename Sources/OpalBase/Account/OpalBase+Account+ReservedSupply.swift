// OpalBase+Account+ReservedSupply.swift

import Foundation

extension _OpalBase.Account {
    public struct ReservedSupply: Sendable {
        public let fungibleAmount: UInt64
        public let shouldIncludeMintingNonFungibleToken: Bool
        public let commitment: Data
        
        public init(fungibleAmount: UInt64,
                    shouldIncludeMintingNonFungibleToken: Bool,
                    commitment: Data = .init()) throws {
            try TokenOperationValidator.requireNonZeroFungibleAmount(fungibleAmount) {
                OpalBase.Account.Error.tokenGenesisFungibleAmountIsZero
            }
            try TokenOperationValidator.validateCommitmentLength(commitment) { maximum, actual in
                OpalBase.Account.Error.tokenGenesisNonFungibleTokenCommitmentTooLong(
                    maximum: maximum,
                    actual: actual
                )
            }
            self.fungibleAmount = fungibleAmount
            self.shouldIncludeMintingNonFungibleToken = shouldIncludeMintingNonFungibleToken
            self.commitment = commitment
        }
    }
}
