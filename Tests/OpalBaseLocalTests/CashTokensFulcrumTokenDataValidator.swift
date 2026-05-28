// CashTokensFulcrumTokenDataValidator.swift

import Foundation
import SwiftFulcrum
import Testing
@testable import OpalBase

@Suite("OpalBase.CashTokens Fulcrum token data", .tags(.unit, .cashTokens))
struct CashTokensFulcrumTokenDataValidator {
    @Test("rejects oversized fungible token amounts")
    func rejectsOversizedFungibleTokenAmounts() throws {
        let oversizedAmount = "9223372036854775808"
        let tokenData = SwiftFulcrum.CashTokens.TokenData(
            amount: oversizedAmount,
            category: String(repeating: "11", count: 32),
            nft: nil
        )

        #expect(throws: OpalBase.CashTokens.Error.invalidFungibleAmountString(oversizedAmount)) {
            _ = try OpalBase.CashTokens.TokenData(swiftFulcrumTokenData: tokenData)
        }
    }

    @Test("rejects RPC-prefixed non-fungible token commitments")
    func rejectRPCPrefixedNonFungibleTokenCommitments() {
        let tokenData = SwiftFulcrum.CashTokens.TokenData(
            amount: "0",
            category: String(repeating: "11", count: 32),
            nft: .init(capability: .none, commitment: "0x12")
        )

        #expect(throws: OpalBase.CashTokens.Error.invalidHexadecimalString) {
            _ = try OpalBase.CashTokens.TokenData(swiftFulcrumTokenData: tokenData)
        }
    }
}
