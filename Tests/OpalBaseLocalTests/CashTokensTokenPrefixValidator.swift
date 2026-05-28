// CashTokensTokenPrefixValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.CashTokens Token Prefix", .tags(.unit, .cashTokens))
struct CashTokensTokenPrefixValidator {
    @Test("decode returns nil token data when no prefix is present")
    func decodeWithoutPrefix() throws {
        let lockingBytecode = Data([0x51, 0x21, 0x00])
        let result = try OpalBase.CashTokens.TokenPrefix.decode(prefixPlusBytecode: lockingBytecode)
        #expect(result.tokenData == nil)
        #expect(result.lockingBytecode == lockingBytecode)
    }
    
    @Test("encode matches valid token prefix vectors")
    func encodeValidVectors() throws {
        #expect(!TokenPrefixTestData.validVectors.isEmpty)
        for vector in TokenPrefixTestData.validVectors {
            let tokenData = try makeTokenData(from: vector.data)
            let encoded = try OpalBase.CashTokens.TokenPrefix.encode(tokenData: tokenData)
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
            
            let result = try OpalBase.CashTokens.TokenPrefix.decode(prefixPlusBytecode: combined)
            let expectedTokenData = try makeTokenData(from: vector.data)
            
            let decodedTokenData = try #require(result.tokenData)
            #expect(decodedTokenData.category.transactionOrderData == expectedTokenData.category.transactionOrderData)
            #expect(decodedTokenData.amount == expectedTokenData.amount)
            #expect(decodedTokenData.nft == expectedTokenData.nft)
            #expect(result.lockingBytecode == trailingBytecode)
        }
    }

    @Test("decode returns zero-based locking bytecode from sliced prefix data")
    func decodeReturnsZeroBasedLockingBytecodeFromSlicedPrefixData() throws {
        let fixture = try #require(TokenPrefixTestData.validVectors.first)
        let prefixData = try Data(hexadecimalString: fixture.prefix)
        let lockingBytecode = OpalBase.Script.p2sh(scriptHash: Data(repeating: 0x55, count: 20)).data
        var combined = prefixData
        combined.append(lockingBytecode)

        let slicedPrefixData = makeSlicedData(from: combined)
        let result = try OpalBase.CashTokens.TokenPrefix.decode(prefixPlusBytecode: slicedPrefixData)

        #expect(slicedPrefixData.startIndex != 0)
        #expect(result.lockingBytecode == lockingBytecode)
        #expect(result.lockingBytecode.startIndex == 0)
    }

    @Test("valid token prefix vectors are internally consistent")
    func validateFixtureConsistency() throws {
        #expect(!TokenPrefixTestData.validVectors.isEmpty)
        for vector in TokenPrefixTestData.validVectors {
            let expectedTokenData = try makeTokenData(from: vector.data)
            let prefixData = try Data(hexadecimalString: vector.prefix)
            let encoded = try OpalBase.CashTokens.TokenPrefix.encode(tokenData: expectedTokenData)
            #expect(encoded == prefixData)
            
            var combined = prefixData
            combined.append(contentsOf: [0x6a, 0x01, 0x01])
            let decoded = try OpalBase.CashTokens.TokenPrefix.decode(prefixPlusBytecode: combined)
            let decodedTokenData = try #require(decoded.tokenData)
            #expect(decodedTokenData.amount == expectedTokenData.amount)
            #expect(decodedTokenData.nft == expectedTokenData.nft)
        }
    }
    
    @Test("decode rejects invalid token prefix vectors")
    func decodeInvalidVectors() throws {
        #expect(!TokenPrefixTestData.invalidVectors.isEmpty)
        for vector in TokenPrefixTestData.invalidVectors {
            let prefixData = try Data(hexadecimalString: vector.prefix)
            #expect(throws: OpalBase.CashTokens.Error.self) {
                _ = try OpalBase.CashTokens.TokenPrefix.decode(prefixPlusBytecode: prefixData)
            }
        }
    }
    
    @Test("encode then decode preserves token data")
    func encodeDecodeRoundTripPreservesTokenData() throws {
        let category = try makeCategoryIdentifier(using: 0x11)
        let nonFungibleToken = try OpalBase.CashTokens.NFT(capability: .mutable, commitment: Data([0x0a, 0x0b]))
        let tokenDataValues = [
            OpalBase.CashTokens.TokenData(category: category, amount: 1, nft: nil),
            OpalBase.CashTokens.TokenData(category: category, amount: nil, nft: nonFungibleToken),
            OpalBase.CashTokens.TokenData(category: category, amount: 42, nft: nonFungibleToken)
        ]
        let trailingBytecode = Data([0x6a, 0x01])
        
        for expectedTokenData in tokenDataValues {
            var combined = try OpalBase.CashTokens.TokenPrefix.encode(tokenData: expectedTokenData)
            combined.append(trailingBytecode)
            
            let result = try OpalBase.CashTokens.TokenPrefix.decode(prefixPlusBytecode: combined)
            let decodedTokenData = try #require(result.tokenData)
            #expect(decodedTokenData == expectedTokenData)
            #expect(result.lockingBytecode == trailingBytecode)
        }
    }
    
    @Test("category bytes are encoded in transaction order")
    func encodeUsesTransactionOrderForCategory() throws {
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data((0..<32).map { UInt8($0) }))
        let tokenData = OpalBase.CashTokens.TokenData(category: category, amount: 1, nft: nil)
        
        let encoded = try OpalBase.CashTokens.TokenPrefix.encode(tokenData: tokenData)
        let encodedCategoryBytes = encoded.dropFirst().prefix(32)
        #expect(encodedCategoryBytes == category.transactionOrderData)
    }
    
    @Test("category identifiers reject prefixed RPC hex")
    func categoryIdentifiersRejectPrefixedRPCHex() {
        let categoryHexadecimal = String(repeating: "a", count: 64)
        
        #expect(throws: OpalBase.CashTokens.Error.invalidHexadecimalString) {
            _ = try OpalBase.CashTokens.CategoryID(hexFromRPC: "0x\(categoryHexadecimal)")
        }
    }

    @Test("NFT decoder rejects prefixed commitment hex")
    func nonFungibleTokenDecoderRejectsPrefixedCommitmentHex() {
        let payload = Data(#"{"capability":"none","commitment":"0x12"}"#.utf8)

        #expect(throws: OpalBase.CashTokens.Error.invalidHexadecimalString) {
            _ = try JSONDecoder().decode(OpalBase.CashTokens.NFT.self, from: payload)
        }
    }
    
    @Test("commitment length bounds are enforced")
    func validateCommitmentLengthBounds() throws {
        let commitmentLengths = [0, 1, 40]
        for commitmentLength in commitmentLengths {
            let commitment = Data(repeating: 0x01, count: commitmentLength)
            let nonFungibleToken = try OpalBase.CashTokens.NFT(capability: .none, commitment: commitment)
            #expect(nonFungibleToken.commitment.count == commitmentLength)
        }
        
        let oversizedCommitment = Data(repeating: 0x02, count: 41)
        #expect(throws: OpalBase.CashTokens.Error.commitmentLengthOutOfRange(minimum: 0, maximum: 40, actual: 41)) {
            _ = try OpalBase.CashTokens.NFT(capability: .none, commitment: oversizedCommitment)
        }
        
        let category = try makeCategoryIdentifier(using: 0x22)
        let oversizedPrefix = makeOversizedCommitmentPrefix(category: category, commitmentByteCount: 41)
        #expect(throws: OpalBase.CashTokens.Error.invalidTokenPrefixCommitmentLength) {
            _ = try OpalBase.CashTokens.TokenPrefix.decode(prefixPlusBytecode: oversizedPrefix)
        }
    }
    
    private func makeTokenData(from fixture: TokenPrefixTokenData) throws -> OpalBase.CashTokens.TokenData {
        let category = try OpalBase.CashTokens.CategoryID(hexFromRPC: fixture.category)
        let amount = try parseAmount(from: fixture.amount)
        let nonFungibleToken = try fixture.nonFungibleToken.map { try makeNonFungibleToken(from: $0) }
        return OpalBase.CashTokens.TokenData(category: category, amount: amount, nft: nonFungibleToken)
    }
    
    private func parseAmount(from amountString: String?) throws -> UInt64? {
        guard let amountString else {
            return nil
        }
        guard let amountValue = UInt64(amountString) else {
            throw OpalBase.CashTokens.Error.invalidFungibleAmountString(amountString)
        }
        return amountValue == 0 ? nil : amountValue
    }
    
    private func makeNonFungibleToken(from fixture: TokenPrefixNonFungibleTokenData) throws -> OpalBase.CashTokens.NFT {
        let capability = try makeNonFungibleCapability(from: fixture.capability)
        let commitment = try Data(hexadecimalString: fixture.commitment)
        return try OpalBase.CashTokens.NFT(capability: capability, commitment: commitment)
    }
    
    private func makeNonFungibleCapability(from capabilityString: String) throws -> OpalBase.CashTokens.NFT.Capability {
        switch capabilityString {
        case "none":
            return .none
        case "mutable":
            return .mutable
        case "minting":
            return .minting
        default:
            throw OpalBase.CashTokens.Error.invalidTokenPrefixCapability
        }
    }
    
    private func makeCategoryIdentifier(using byte: UInt8) throws -> OpalBase.CashTokens.CategoryID {
        try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: byte, count: 32))
    }
    
    private func makeOversizedCommitmentPrefix(category: OpalBase.CashTokens.CategoryID,
                                               commitmentByteCount: UInt8) -> Data {
        var data = Data()
        data.append(OpalBase.CashTokens.TokenPrefix.prefixToken)
        data.append(category.transactionOrderData)
        data.append(0x60)
        data.append(commitmentByteCount)
        data.append(Data(repeating: 0x00, count: Int(commitmentByteCount)))
        return data
    }

    private func makeSlicedData(from data: Data) -> Data {
        var paddedData = Data([0x00])
        paddedData.append(data)
        return paddedData[paddedData.index(after: paddedData.startIndex)...]
    }
}
