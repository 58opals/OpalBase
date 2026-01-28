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
    
    @Test("valid token prefix vectors are internally consistent")
    func testValidateFixtureConsistency() throws {
        #expect(!TokenPrefixFixtureStore.validVectors.isEmpty)
        for vector in TokenPrefixFixtureStore.validVectors {
            let expectedTokenData = try makeTokenData(from: vector.data)
            let prefixData = try Data(hexadecimalString: vector.prefix)
            let encoded = try CashTokens.TokenPrefix.encode(tokenData: expectedTokenData)
            #expect(encoded == prefixData)
            
            var combined = prefixData
            combined.append(contentsOf: [0x6a, 0x01, 0x01])
            let decoded = try CashTokens.TokenPrefix.decode(prefixPlusBytecode: combined)
            let decodedTokenData = try #require(decoded.tokenData)
            #expect(decodedTokenData.amount == expectedTokenData.amount)
            #expect(decodedTokenData.nft == expectedTokenData.nft)
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
    
    @Test("encode then decode preserves token data")
    func testEncodeDecodeRoundTripPreservesTokenData() throws {
        let category = try makeCategoryIdentifier(using: 0x11)
        let nonFungibleToken = try CashTokens.NFT(capability: .mutable, commitment: Data([0x0a, 0x0b]))
        let tokenDataValues = [
            CashTokens.TokenData(category: category, amount: 1, nft: nil),
            CashTokens.TokenData(category: category, amount: nil, nft: nonFungibleToken),
            CashTokens.TokenData(category: category, amount: 42, nft: nonFungibleToken)
        ]
        let trailingBytecode = Data([0x6a, 0x01])
        
        for expectedTokenData in tokenDataValues {
            var combined = try CashTokens.TokenPrefix.encode(tokenData: expectedTokenData)
            combined.append(trailingBytecode)
            
            let result = try CashTokens.TokenPrefix.decode(prefixPlusBytecode: combined)
            let decodedTokenData = try #require(result.tokenData)
            #expect(decodedTokenData == expectedTokenData)
            #expect(result.lockingBytecode == trailingBytecode)
        }
    }
    
    @Test("category bytes are encoded in transaction order")
    func testEncodeUsesTransactionOrderForCategory() throws {
        let category = try CashTokens.CategoryID(transactionOrderData: Data((0..<32).map { UInt8($0) }))
        let tokenData = CashTokens.TokenData(category: category, amount: 1, nft: nil)
        
        let encoded = try CashTokens.TokenPrefix.encode(tokenData: tokenData)
        let encodedCategoryBytes = encoded.dropFirst().prefix(32)
        #expect(encodedCategoryBytes == category.transactionOrderData)
    }
    
    @Test("commitment length bounds are enforced")
    func testCommitmentLengthBounds() throws {
        let commitmentLengths = [0, 1, 40]
        for commitmentLength in commitmentLengths {
            let commitment = Data(repeating: 0x01, count: commitmentLength)
            let nonFungibleToken = try CashTokens.NFT(capability: .none, commitment: commitment)
            #expect(nonFungibleToken.commitment.count == commitmentLength)
        }
        
        let oversizedCommitment = Data(repeating: 0x02, count: 41)
        let didThrowCommitmentLengthOutOfRange: Bool
        do {
            _ = try CashTokens.NFT(capability: .none, commitment: oversizedCommitment)
            didThrowCommitmentLengthOutOfRange = false
        } catch CashTokens.Error.commitmentLengthOutOfRange {
            didThrowCommitmentLengthOutOfRange = true
        } catch {
            didThrowCommitmentLengthOutOfRange = false
        }
        #expect(didThrowCommitmentLengthOutOfRange)
        
        let category = try makeCategoryIdentifier(using: 0x22)
        let oversizedPrefix = makeOversizedCommitmentPrefix(category: category, commitmentByteCount: 41)
        #expect(throws: CashTokens.Error.invalidTokenPrefixCommitmentLength) {
            _ = try CashTokens.TokenPrefix.decode(prefixPlusBytecode: oversizedPrefix)
        }
    }
    
    private func makeTokenData(from fixture: TokenPrefixTokenDataFixture) throws -> CashTokens.TokenData {
        let category = try CashTokens.CategoryID(hexFromRPC: fixture.category)
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
    
    private func makeCategoryIdentifier(using byte: UInt8) throws -> CashTokens.CategoryID {
        try CashTokens.CategoryID(transactionOrderData: Data(repeating: byte, count: 32))
    }
    
    private func makeOversizedCommitmentPrefix(category: CashTokens.CategoryID,
                                               commitmentByteCount: UInt8) -> Data {
        var data = Data()
        data.append(CashTokens.TokenPrefix.prefixToken)
        data.append(category.transactionOrderData)
        data.append(0x60)
        data.append(commitmentByteCount)
        data.append(Data(repeating: 0x00, count: Int(commitmentByteCount)))
        return data
    }
}
