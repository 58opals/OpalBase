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
            try TokenGenesisValidation.validateFungibleAmount(fungibleAmount)
            try TokenGenesisValidation.validateCommitment(commitment)
            self.fungibleAmount = fungibleAmount
            self.shouldIncludeMintingNonFungibleToken = shouldIncludeMintingNonFungibleToken
            self.commitment = Data(commitment)
        }
    }
}
