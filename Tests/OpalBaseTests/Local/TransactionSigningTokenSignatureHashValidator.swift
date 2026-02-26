import Foundation
import Testing
@testable import OpalBase

@Suite("TransactionModel signing token signature hash", .tags(.unit, .cashTokens))
struct TransactionSigningTokenSignatureHashValidator {
    @Test("signature hash includes token prefix when spending token output")
    func signatureHashIncludesTokenPrefixWhenSpendingTokenOutput() throws {
        let lockingScript = try makeLockingScript()
        let transaction = makeTransaction(lockingScript: lockingScript)
        let tokenData = try makeTokenData()
        let outputBeingSpent = TransactionModel.OutputModel(value: 10_000,
                                                  lockingScript: lockingScript,
                                                  tokenData: tokenData)
        let preimage = try transaction.generatePreimage(for: 0,
                                                        hashType: .makeAll(),
                                                        outputBeingSpent: outputBeingSpent)
        let message = ECDSAModel.MessageModel.makeDoubleSHA256(preimage)
        let messageDigest = try message.makeConsensusDigest32()
        let expectedDigest = try Data(hexadecimalString: "c9c908b5f351dcc1d2e6b5966a48c5be1be5a8f5e3c426efa5e97aacb8f971e7")
        
        #expect(messageDigest == expectedDigest)
    }
    
    @Test("signature hash for non-token output is unchanged")
    func signatureHashForNonTokenOutputIsUnchanged() throws {
        let lockingScript = try makeLockingScript()
        let transaction = makeTransaction(lockingScript: lockingScript)
        let outputBeingSpent = TransactionModel.OutputModel(value: 10_000,
                                                  lockingScript: lockingScript,
                                                  tokenData: nil)
        let preimage = try transaction.generatePreimage(for: 0,
                                                        hashType: .makeAll(),
                                                        outputBeingSpent: outputBeingSpent)
        let message = ECDSAModel.MessageModel.makeDoubleSHA256(preimage)
        let messageDigest = try message.makeConsensusDigest32()
        let expectedDigest = try Data(hexadecimalString: "e62ddb675df41732686246b8f0f9f7415da321b4a9e5a4e9d5057551a32594b7")
        
        #expect(messageDigest == expectedDigest)
    }
    
    private func makeTransaction(lockingScript: Data) -> TransactionModel {
        let previousTransactionHash = TransactionModel.HashModel(naturalOrder: Data(repeating: 0x11, count: 32))
        let input = TransactionModel.InputModel(previousTransactionHash: previousTransactionHash,
                                      previousTransactionOutputIndex: 0,
                                      unlockingScript: Data(),
                                      sequence: 0xffffffff)
        let output = TransactionModel.OutputModel(value: 9_000, lockingScript: lockingScript)
        return TransactionModel(version: 2, inputs: [input], outputs: [output], lockTime: 0)
    }
    
    private func makeLockingScript() throws -> Data {
        let lockingScriptHexadecimal = "76a914" + String(repeating: "22", count: 20) + "88ac"
        return try Data(hexadecimalString: lockingScriptHexadecimal)
    }
    
    private func makeTokenData() throws -> CashTokensModel.TokenData {
        let fixture = try #require(TokenPrefixTestData.validVectors.first)
        return try makeTokenData(from: fixture.data)
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
}
