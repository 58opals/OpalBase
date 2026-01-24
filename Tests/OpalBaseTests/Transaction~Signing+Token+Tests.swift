import Foundation
import Testing
@testable import OpalBase

@Suite("Transaction signing token signature hash", .tags(.unit, .cashTokens))
struct TransactionSigningTokenSignatureHashTests {
    @Test("signature hash includes token prefix when spending token output")
    func testSignatureHashIncludesTokenPrefixWhenSpendingTokenOutput() throws {
        let lockingScript = try makeLockingScript()
        let transaction = makeTransaction(lockingScript: lockingScript)
        let tokenData = try makeTokenData()
        let outputBeingSpent = Transaction.Output(value: 10_000,
                                                  lockingScript: lockingScript,
                                                  tokenData: tokenData)
        let preimage = try transaction.generatePreimage(for: 0,
                                                        hashType: .makeAll(),
                                                        outputBeingSpent: outputBeingSpent)
        let message = ECDSA.Message.makeDoubleSHA256(preimage)
        let messageDigest = try message.makeConsensusDigest32()
        let expectedDigest = try Data(hexadecimalString: "c9c908b5f351dcc1d2e6b5966a48c5be1be5a8f5e3c426efa5e97aacb8f971e7")
        
        #expect(messageDigest == expectedDigest)
    }
    
    @Test("signature hash for non-token output is unchanged")
    func testSignatureHashForNonTokenOutputIsUnchanged() throws {
        let lockingScript = try makeLockingScript()
        let transaction = makeTransaction(lockingScript: lockingScript)
        let outputBeingSpent = Transaction.Output(value: 10_000,
                                                  lockingScript: lockingScript,
                                                  tokenData: nil)
        let preimage = try transaction.generatePreimage(for: 0,
                                                        hashType: .makeAll(),
                                                        outputBeingSpent: outputBeingSpent)
        let message = ECDSA.Message.makeDoubleSHA256(preimage)
        let messageDigest = try message.makeConsensusDigest32()
        let expectedDigest = try Data(hexadecimalString: "e62ddb675df41732686246b8f0f9f7415da321b4a9e5a4e9d5057551a32594b7")
        
        #expect(messageDigest == expectedDigest)
    }
    
    private func makeTransaction(lockingScript: Data) -> Transaction {
        let previousTransactionHash = Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))
        let input = Transaction.Input(previousTransactionHash: previousTransactionHash,
                                      previousTransactionOutputIndex: 0,
                                      unlockingScript: Data(),
                                      sequence: 0xffffffff)
        let output = Transaction.Output(value: 9_000, lockingScript: lockingScript)
        return Transaction(version: 2, inputs: [input], outputs: [output], lockTime: 0)
    }
    
    private func makeLockingScript() throws -> Data {
        let lockingScriptHexadecimal = "76a914" + String(repeating: "22", count: 20) + "88ac"
        return try Data(hexadecimalString: lockingScriptHexadecimal)
    }
    
    private func makeTokenData() throws -> CashTokens.TokenData {
        let fixture = try #require(TokenPrefixFixtureStore.validVectors.first)
        return try makeTokenData(from: fixture.data)
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
