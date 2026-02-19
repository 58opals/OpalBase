import Foundation
import Testing
@testable import OpalBase

enum AddressBookCashTokensTestData {
    static func makeAddressBook() async throws -> Address.Book {
        let mnemonic = try Mnemonic(words: [
            "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
            "abandon", "abandon", "abandon", "abandon", "abandon", "about",
        ])

        let rootExtendedPrivateKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))

        return try await Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: .init(rawIndexInteger: 0),
            gapLimit: 2
        )
    }

    static func makeTokenData() throws -> CashTokens.TokenData {
        let fixture = try #require(TokenPrefixTestData.validVectors.first)
        return try makeTokenData(from: fixture.data)
    }

    static func makeTokenData(from fixture: TokenPrefixTokenData) throws -> CashTokens.TokenData {
        let category = try CashTokens.CategoryID(hexFromRPC: fixture.category)
        let amount = try parseAmount(from: fixture.amount)
        let nonFungibleToken = try fixture.nonFungibleToken.map { try makeNonFungibleToken(from: $0) }

        return CashTokens.TokenData(category: category, amount: amount, nft: nonFungibleToken)
    }

    static func parseAmount(from amountString: String?) throws -> UInt64? {
        guard let amountString else { return nil }
        guard let amountValue = UInt64(amountString) else {
            throw CashTokens.Error.invalidFungibleAmountString(amountString)
        }
        return amountValue == 0 ? nil : amountValue
    }

    static func makeNonFungibleToken(from fixture: TokenPrefixNonFungibleTokenData) throws -> CashTokens.NFT {
        let capability = try makeNonFungibleCapability(from: fixture.capability)
        let commitment = try Data(hexadecimalString: fixture.commitment)
        return try CashTokens.NFT(capability: capability, commitment: commitment)
    }

    static func makeNonFungibleCapability(from capabilityString: String) throws -> CashTokens.NFT.Capability {
        switch capabilityString {
        case "none":
            return .none
        case "mutable":
            return .mutable
        case "minting":
            return .minting
        default:
            throw CashTokens.Error.invalidTokenPrefixCapability
        }
    }
}
