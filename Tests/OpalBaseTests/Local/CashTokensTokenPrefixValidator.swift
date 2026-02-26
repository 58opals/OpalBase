import Foundation
import Testing
@testable import OpalBase

@Suite("CashTokensModel Token Prefix", .tags(.unit, .cashTokens))
struct CashTokensTokenPrefixValidator {
    @Test("decode returns nil token data when no prefix is present")
    func decodeWithoutPrefix() throws {
        let lockingBytecode = Data([0x51, 0x21, 0x00])
        let result = try CashTokensModel.TokenPrefixModel.decode(prefixPlusBytecode: lockingBytecode)
        #expect(result.tokenData == nil)
        #expect(result.lockingBytecode == lockingBytecode)
    }
    
    @Test("encode matches valid token prefix vectors")
    func encodeValidVectors() throws {
        #expect(!TokenPrefixTestData.validVectors.isEmpty)
        for vector in TokenPrefixTestData.validVectors {
            let tokenData = try makeTokenData(from: vector.data)
            let encoded = try CashTokensModel.TokenPrefixModel.encode(tokenData: tokenData)
            #expect(encoded.hexadecimalString == vector.prefix)
        }
    }
    
    @Test("decode matches valid token prefix vectors")
    func decodeValidVectors() throws {
        #expect(!TokenPrefixTestData.validVectors.isEmpty)
        let trailingBytecode = Data([0x6a, 0x01, 0x01])
        for vector in TokenPrefixTestData.validVectors {
            let prefixData = try Data(hexadecimalString: vector.prefix)
            var combined = prefixData
            combined.append(trailingBytecode)
            
            let result = try CashTokensModel.TokenPrefixModel.decode(prefixPlusBytecode: combined)
            let expectedTokenData = try makeTokenData(from: vector.data)
            
            let decodedTokenData = try #require(result.tokenData)
            #expect(decodedTokenData.category.transactionOrderData == expectedTokenData.category.transactionOrderData)
            #expect(decodedTokenData.amount == expectedTokenData.amount)
            #expect(decodedTokenData.nft == expectedTokenData.nft)
            #expect(result.lockingBytecode == trailingBytecode)
        }
    }
    
    @Test("valid token prefix vectors are internally consistent")
    func validateFixtureConsistency() throws {
        #expect(!TokenPrefixTestData.validVectors.isEmpty)
        for vector in TokenPrefixTestData.validVectors {
            let expectedTokenData = try makeTokenData(from: vector.data)
            let prefixData = try Data(hexadecimalString: vector.prefix)
            let encoded = try CashTokensModel.TokenPrefixModel.encode(tokenData: expectedTokenData)
            #expect(encoded == prefixData)
            
            var combined = prefixData
            combined.append(contentsOf: [0x6a, 0x01, 0x01])
            let decoded = try CashTokensModel.TokenPrefixModel.decode(prefixPlusBytecode: combined)
            let decodedTokenData = try #require(decoded.tokenData)
            #expect(decodedTokenData.amount == expectedTokenData.amount)
            #expect(decodedTokenData.nft == expectedTokenData.nft)
        }
    }
    
    @Test("decode rejects invalid token prefix vectors")
    func decodeInvalidVectors() {
        #expect(!TokenPrefixTestData.invalidVectors.isEmpty)
        for vector in TokenPrefixTestData.invalidVectors {
            let hasThrown: Bool
            do {
                let prefixData = try Data(hexadecimalString: vector.prefix)
                _ = try CashTokensModel.TokenPrefixModel.decode(prefixPlusBytecode: prefixData)
                hasThrown = false
            } catch {
                hasThrown = true
            }
            #expect(hasThrown)
        }
    }
    
    @Test("encode then decode preserves token data")
    func encodeDecodeRoundTripPreservesTokenData() throws {
        let category = try makeCategoryIdentifier(using: 0x11)
        let nonFungibleToken = try CashTokensModel.NFTModel(capability: .mutable, commitment: Data([0x0a, 0x0b]))
        let tokenDataValues = [
            CashTokensModel.TokenData(category: category, amount: 1, nft: nil),
            CashTokensModel.TokenData(category: category, amount: nil, nft: nonFungibleToken),
            CashTokensModel.TokenData(category: category, amount: 42, nft: nonFungibleToken)
        ]
        let trailingBytecode = Data([0x6a, 0x01])
        
        for expectedTokenData in tokenDataValues {
            var combined = try CashTokensModel.TokenPrefixModel.encode(tokenData: expectedTokenData)
            combined.append(trailingBytecode)
            
            let result = try CashTokensModel.TokenPrefixModel.decode(prefixPlusBytecode: combined)
            let decodedTokenData = try #require(result.tokenData)
            #expect(decodedTokenData == expectedTokenData)
            #expect(result.lockingBytecode == trailingBytecode)
        }
    }
    
    @Test("category bytes are encoded in transaction order")
    func encodeUsesTransactionOrderForCategory() throws {
        let category = try CashTokensModel.CategoryIDModel(transactionOrderData: Data((0..<32).map { UInt8($0) }))
        let tokenData = CashTokensModel.TokenData(category: category, amount: 1, nft: nil)
        
        let encoded = try CashTokensModel.TokenPrefixModel.encode(tokenData: tokenData)
        let encodedCategoryBytes = encoded.dropFirst().prefix(32)
        #expect(encodedCategoryBytes == category.transactionOrderData)
    }
    
    @Test("commitment length bounds are enforced")
    func commitmentLengthBounds() throws {
        let commitmentLengths = [0, 1, 40]
        for commitmentLength in commitmentLengths {
            let commitment = Data(repeating: 0x01, count: commitmentLength)
            let nonFungibleToken = try CashTokensModel.NFTModel(capability: .none, commitment: commitment)
            #expect(nonFungibleToken.commitment.count == commitmentLength)
        }
        
        let oversizedCommitment = Data(repeating: 0x02, count: 41)
        let hasThrownCommitmentLengthOutOfRange: Bool
        do {
            _ = try CashTokensModel.NFTModel(capability: .none, commitment: oversizedCommitment)
            hasThrownCommitmentLengthOutOfRange = false
        } catch CashTokensModel.Error.commitmentLengthOutOfRange {
            hasThrownCommitmentLengthOutOfRange = true
        } catch {
            hasThrownCommitmentLengthOutOfRange = false
        }
        #expect(hasThrownCommitmentLengthOutOfRange)
        
        let category = try makeCategoryIdentifier(using: 0x22)
        let oversizedPrefix = makeOversizedCommitmentPrefix(category: category, commitmentByteCount: 41)
        #expect(throws: CashTokensModel.Error.invalidTokenPrefixCommitmentLength) {
            _ = try CashTokensModel.TokenPrefixModel.decode(prefixPlusBytecode: oversizedPrefix)
        }
    }
    
    private func makeTokenData(from fixture: TokenPrefixTokenData) throws -> CashTokensModel.TokenData {
        let category = try CashTokensModel.CategoryIDModel(hexFromRPC: fixture.category)
        let amount = try parseAmount(from: fixture.amount)
        let nonFungibleToken = try fixture.nonFungibleToken.map { try makeNonFungibleToken(from: $0) }
        return CashTokensModel.TokenData(category: category, amount: amount, nft: nonFungibleToken)
    }
    
    private func parseAmount(from amountString: String?) throws -> UInt64? {
        guard let amountString else {
            return nil
        }
        guard let amountValue = UInt64(amountString) else {
            throw CashTokensModel.Error.invalidFungibleAmountString(amountString)
        }
        return amountValue == 0 ? nil : amountValue
    }
    
    private func makeNonFungibleToken(from fixture: TokenPrefixNonFungibleTokenData) throws -> CashTokensModel.NFTModel {
        let capability = try makeNonFungibleCapability(from: fixture.capability)
        let commitment = try Data(hexadecimalString: fixture.commitment)
        return try CashTokensModel.NFTModel(capability: capability, commitment: commitment)
    }
    
    private func makeNonFungibleCapability(from capabilityString: String) throws -> CashTokensModel.NFTModel.Capability {
        switch capabilityString {
        case "none":
            return .none
        case "mutable":
            return .mutable
        case "minting":
            return .minting
        default:
            throw CashTokensModel.Error.invalidTokenPrefixCapability
        }
    }
    
    private func makeCategoryIdentifier(using byte: UInt8) throws -> CashTokensModel.CategoryIDModel {
        try CashTokensModel.CategoryIDModel(transactionOrderData: Data(repeating: byte, count: 32))
    }
    
    private func makeOversizedCommitmentPrefix(category: CashTokensModel.CategoryIDModel,
                                               commitmentByteCount: UInt8) -> Data {
        var data = Data()
        data.append(CashTokensModel.TokenPrefixModel.prefixToken)
        data.append(category.transactionOrderData)
        data.append(0x60)
        data.append(commitmentByteCount)
        data.append(Data(repeating: 0x00, count: Int(commitmentByteCount)))
        return data
    }
}
