// CashTokensFulcrumTokenDataValidator.swift

import Foundation
import SwiftFulcrum
import Testing
@testable import OpalBase

@Suite("OpalBase.CashTokens Fulcrum token data", .tags(.unit, .cashTokens))
struct CashTokensFulcrumTokenDataValidator {
    private static let validCategoryIdentifier = String(repeating: "11", count: 32)

    @Test("rejects oversized fungible token amounts")
    func rejectOversizedFungibleTokenAmounts() throws {
        let oversizedAmount = "9223372036854775808"
        let tokenData = Self.makeSwiftFulcrumTokenData(amount: oversizedAmount)

        #expect(throws: OpalBase.CashTokens.Error.invalidFungibleAmountString(oversizedAmount)) {
            _ = try OpalBase.CashTokens.TokenData(swiftFulcrumTokenData: tokenData)
        }
    }

    @Test("rejects category-only token data")
    func rejectCategoryOnlyTokenData() throws {
        let tokenData = Self.makeSwiftFulcrumTokenData(amount: "0")

        #expect(throws: OpalBase.CashTokens.Error.invalidTokenPrefix) {
            _ = try OpalBase.CashTokens.TokenData(swiftFulcrumTokenData: tokenData)
        }
    }

    @Test("accepts fungible-only token data")
    func acceptFungibleOnlyTokenData() throws {
        let tokenData = Self.makeSwiftFulcrumTokenData(amount: "1")

        let decodedTokenData = try OpalBase.CashTokens.TokenData(swiftFulcrumTokenData: tokenData)

        #expect(decodedTokenData.amount == 1)
        #expect(decodedTokenData.nft == nil)
    }

    @Test("accepts non-fungible-only token data")
    func acceptNonFungibleOnlyTokenData() throws {
        let tokenData = Self.makeSwiftFulcrumTokenData(
            amount: "0",
            nft: .init(capability: .mutable, commitment: "12")
        )

        let decodedTokenData = try OpalBase.CashTokens.TokenData(swiftFulcrumTokenData: tokenData)

        #expect(decodedTokenData.amount == nil)
        #expect(decodedTokenData.nft?.capability == .mutable)
        #expect(decodedTokenData.nft?.commitment == Data([0x12]))
    }

    @Test("rejects RPC-prefixed non-fungible token commitments")
    func rejectRPCPrefixedNonFungibleTokenCommitments() {
        let tokenData = Self.makeSwiftFulcrumTokenData(
            amount: "0",
            nft: .init(capability: .none, commitment: "0x12")
        )

        #expect(throws: OpalBase.CashTokens.Error.invalidHexadecimalString) {
            _ = try OpalBase.CashTokens.TokenData(swiftFulcrumTokenData: tokenData)
        }
    }

    private static func makeSwiftFulcrumTokenData(
        amount: String,
        nft: SwiftFulcrum.CashTokens.TokenData.NFT? = nil
    ) -> SwiftFulcrum.CashTokens.TokenData {
        SwiftFulcrum.CashTokens.TokenData(
            amount: amount,
            category: validCategoryIdentifier,
            nft: nft
        )
    }
}
