import Foundation
import Testing
@testable import OpalBase

@Suite("CashTokens Token Prefix", .tags(.unit, .cashTokens))
struct CashTokensTokenPrefixTests {
    @Test("decode returns nil token data when no prefix is present")
    func testDecodeWithoutPrefix() throws {
        let lockingBytecode = Data([0x51, 0x21, 0x00])
        let result = try CashTokens.TokenPrefix.decode(prefixPlusBytecode: lockingBytecode)
        #expect(result.tokenData == nil)
        #expect(result.lockingBytecode == lockingBytecode)
    }
    
    @Test("encode matches valid token prefix vectors")
    func testEncodeValidVectors() throws {
        #expect(!TokenPrefixFixtureStore.validVectors.isEmpty)
        for vector in TokenPrefixFixtureStore.validVectors {
            let tokenData = try makeTokenData(from: vector.data)
            let encoded = try CashTokens.TokenPrefix.encode(tokenData: tokenData)
            #expect(encoded.hexadecimalString == vector.prefix)
        }
    }
    
    @Test("decode matches valid token prefix vectors")
    func testDecodeValidVectors() throws {
        #expect(!TokenPrefixFixtureStore.validVectors.isEmpty)
        let trailingBytecode = Data([0x6a, 0x01, 0x01])
        for vector in TokenPrefixFixtureStore.validVectors {
            let prefixData = try Data(hexadecimalString: vector.prefix)
            var combined = prefixData
            combined.append(trailingBytecode)
            
            let result = try CashTokens.TokenPrefix.decode(prefixPlusBytecode: combined)
            let expectedTokenData = try makeTokenData(from: vector.data)
            
            let decodedTokenData = try #require(result.tokenData)
            #expect(decodedTokenData.category.transactionOrderData == expectedTokenData.category.transactionOrderData)
            #expect(decodedTokenData.amount == expectedTokenData.amount)
            #expect(decodedTokenData.nft == expectedTokenData.nft)
            #expect(result.lockingBytecode == trailingBytecode)
        }
    }
    
    @Test("decode rejects invalid token prefix vectors")
    func testDecodeInvalidVectors() {
        #expect(!TokenPrefixFixtureStore.invalidVectors.isEmpty)
        for vector in TokenPrefixFixtureStore.invalidVectors {
            let didThrow: Bool
            do {
                let prefixData = try Data(hexadecimalString: vector.prefix)
                _ = try CashTokens.TokenPrefix.decode(prefixPlusBytecode: prefixData)
                didThrow = false
            } catch {
                didThrow = true
            }
            #expect(didThrow)
        }
    }
    
    private func makeTokenData(from fixture: TokenPrefixTokenDataFixture) throws -> CashTokens.TokenData {
        let categoryData = try Data(hexadecimalString: fixture.category)
        let category = try CashTokens.CategoryID(transactionOrderData: categoryData)
        let amount = try parseAmount(from: fixture.amount)
        let nonFungibleToken = try fixture.nonFungibleToken.map { try makeNonFungibleToken(from: $0) }
        return CashTokens.TokenData(category: category, amount: amount, nft: nonFungibleToken)
    }
    
    private func parseAmount(from amountString: String?) throws -> UInt64? {
        guard let amountString else {
            return nil
        }
        guard let amountValue = UInt64(amountString) else {
            throw CashTokens.Error.invalidFungibleAmountString(amountString)
        }
        return amountValue == 0 ? nil : amountValue
    }
    
    private func makeNonFungibleToken(from fixture: TokenPrefixNonFungibleTokenFixture) throws -> CashTokens.NFT {
        let capability = try makeNonFungibleCapability(from: fixture.capability)
        let commitment = try Data(hexadecimalString: fixture.commitment)
        return try CashTokens.NFT(capability: capability, commitment: commitment)
    }
    
    private func makeNonFungibleCapability(from capabilityString: String) throws -> CashTokens.NFT.Capability {
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
