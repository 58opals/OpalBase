// CashTokensTokenDataValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("CashTokens category and non-fungible data", .tags(.unit, .cashTokens))
struct CashTokensTokenDataValidator {
    @Test("category identifiers reject invalid RPC hex", arguments: invalidCategoryIdentifiers)
    func rejectInvalidCategoryIdentifier(
        description: String,
        hexadecimalString: String,
        expectedError: OpalBase.CashTokens.Error
    ) {
        #expect(throws: expectedError) {
            _ = try OpalBase.CashTokens.CategoryID(hexFromRPC: hexadecimalString)
        }
    }

    @Test("category identifiers normalize sliced transaction-order data")
    func normalizeSlicedCategoryIdentifier() throws {
        let transactionOrderData = Data(repeating: 0x44, count: 32)
        let paddedData = Data([0x00]) + transactionOrderData + Data([0xff])
        let slicedData = paddedData[paddedData.index(after: paddedData.startIndex)..<paddedData.index(before: paddedData.endIndex)]

        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: slicedData)

        #expect(slicedData.startIndex != 0)
        #expect(category.transactionOrderData == transactionOrderData)
        #expect(category.transactionOrderData.startIndex == 0)
    }

    @Test("NFT decoder rejects prefixed commitment hex")
    func rejectPrefixedCommitmentHex() {
        let payload = Data(#"{"capability":"none","commitment":"0x12"}"#.utf8)

        #expect(throws: OpalBase.CashTokens.Error.invalidHexadecimalString) {
            _ = try JSONDecoder().decode(OpalBase.CashTokens.NFT.self, from: payload)
        }
    }

    @Test("NFT coding round-trips empty commitments")
    func roundTripEmptyCommitment() throws {
        let token = try OpalBase.CashTokens.NFT(capability: .none, commitment: Data())
        let encoded = try JSONEncoder().encode(token)
        let decoded = try JSONDecoder().decode(OpalBase.CashTokens.NFT.self, from: encoded)

        #expect(decoded == token)
    }

    @Test("NFTs normalize sliced commitments")
    func normalizeSlicedCommitment() throws {
        let commitment = Data([0x0a, 0x0b])
        let paddedCommitment = Data([0x00]) + commitment + Data([0xff])
        let slicedCommitment = paddedCommitment[paddedCommitment.index(after: paddedCommitment.startIndex)..<paddedCommitment.index(before: paddedCommitment.endIndex)]

        let token = try OpalBase.CashTokens.NFT(capability: .mutable, commitment: slicedCommitment)

        #expect(slicedCommitment.startIndex != 0)
        #expect(token.commitment == commitment)
        #expect(token.commitment.startIndex == 0)
    }

    @Test("valid commitment lengths are accepted", arguments: [0, 1, 40])
    func acceptSupportedCommitmentLengths(_ commitmentLength: Int) throws {
        let commitment = Data(repeating: 0x01, count: commitmentLength)
        let nonFungibleToken = try OpalBase.CashTokens.NFT(capability: .none, commitment: commitment)
        #expect(nonFungibleToken.commitment.count == commitmentLength)
    }

    @Test("oversized commitment lengths are rejected")
    func rejectOversizedCommitment() {
        let oversizedCommitment = Data(repeating: 0x02, count: 41)
        #expect(throws: OpalBase.CashTokens.Error.commitmentLengthOutOfRange(minimum: 0, maximum: 40, actual: 41)) {
            _ = try OpalBase.CashTokens.NFT(capability: .none, commitment: oversizedCommitment)
        }
    }

    private static let invalidCategoryIdentifiers: [(String, String, OpalBase.CashTokens.Error)] = [
        (
            "prefixed hex",
            "0x\(String(repeating: "a", count: 64))",
            .invalidHexadecimalString
        ),
        (
            "oversized hex",
            String(repeating: "a", count: 4_096),
            .categoryIdentifierLengthMismatch(expected: 32, actual: 2_048)
        )
    ]
}
