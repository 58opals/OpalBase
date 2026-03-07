// TransactionOutputTokenValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Transaction output encoding", .tags(.unit, .cashTokens))
struct TransactionOutputTokenValidator {
    @Test("output round trip without token data")
    func outputRoundTripWithoutTokenData() throws {
        let output = OpalBase.Transaction.OutputModel(value: 546, lockingScript: Data([0x51]))
        
        let encoded = try output.encode()
        let (decoded, bytesRead) = try OpalBase.Transaction.OutputModel.decode(from: encoded)
        let reencoded = try decoded.encode()
        
        #expect(bytesRead == encoded.count)
        #expect(decoded == output)
        #expect(reencoded == encoded)
    }
    
    @Test("output round trip with token data matches expected hexadecimal")
    func outputRoundTripWithTokenDataMatchesExpectedHexadecimal() throws {
        let fixture = try #require(TokenPrefixTestData.validVectors.first)
        let tokenData = try makeTokenData(from: fixture.data)
        let lockingScript = Data([0x51])
        let output = OpalBase.Transaction.OutputModel(value: 546, lockingScript: lockingScript, tokenData: tokenData)
        
        let encoded = try output.encode()
        let expectedHexadecimal = "2202000000000000" + "24" + fixture.prefix + "51"
        
        #expect(encoded.hexadecimalString == expectedHexadecimal)
        
        let (decoded, bytesRead) = try OpalBase.Transaction.OutputModel.decode(from: encoded)
        let reencoded = try decoded.encode()
        
        #expect(bytesRead == encoded.count)
        #expect(decoded.value == output.value)
        #expect(decoded.lockingScript == lockingScript)
        #expect(decoded.tokenData == tokenData)
        #expect(reencoded == encoded)
    }
    
    private func makeTokenData(from fixture: TokenPrefixTokenData) throws -> OpalBase.CashTokens.TokenData {
        let category = try OpalBase.CashTokens.CategoryIDModel(hexFromRPC: fixture.category)
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
    
    private func makeNonFungibleToken(from fixture: TokenPrefixNonFungibleTokenData) throws -> OpalBase.CashTokens.NFTModel {
        let capability = try makeNonFungibleCapability(from: fixture.capability)
        let commitment = try Data(hexadecimalString: fixture.commitment)
        return try OpalBase.CashTokens.NFTModel(capability: capability, commitment: commitment)
    }
    
    private func makeNonFungibleCapability(from capabilityString: String) throws -> OpalBase.CashTokens.NFTModel.Capability {
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
}

