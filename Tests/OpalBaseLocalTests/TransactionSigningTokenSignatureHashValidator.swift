// TransactionSigningTokenSignatureHashValidator.swift

import Foundation
import OpalCrypto
import Testing
import OpalBaseTestSupport
@testable import OpalBase
@testable import OpalBaseCore

@Suite("OpalBase.Transaction signing token signature hash", .tags(.unit, .cashTokens))
struct TransactionSigningTokenSignatureHashValidator {
    @Test(
        "token signature hash matches BCHN serialization vectors",
        arguments: [
            (25, false, "535eaae815ef64ee013325f56790c4006d51b48a72663ae760802a79752fab6f"),
            (25, true, "2399b9126ff61714831505219ea189871432dce5a72200ff0d1a1dcfb55c1d0c"),
            (253, false, "b491223c855d32259cf5bf4107f263862edc2fac6673862943409cae52f6d4b2"),
            (253, true, "e82c778758727f47f64d45cd845945c9372097ea19b7840542175f58db459fe9"),
        ]
    )
    func signatureHashIncludesTokenPrefixWhenSpendingTokenOutput(
        lockingScriptLength: Int,
        includesUnspentTransactionOutputs: Bool,
        expectedDigestHex: String
    ) throws {
        var lockingScript = try makeLockingScript()
        lockingScript.append(Data(repeating: 0x61, count: lockingScriptLength - lockingScript.count))
        let transaction = makeTransaction(lockingScript: lockingScript)
        let tokenData = try makeTokenData()
        let outputBeingSpent = OpalBase.Transaction.Output(
            value: 10_000,
            lockingScript: lockingScript,
            tokenData: tokenData
        )
        let preimage = try transaction.generatePreimage(
            for: 0,
            hashType: .makeAll(includesUnspentTransactionOutputs: includesUnspentTransactionOutputs),
            outputBeingSpent: outputBeingSpent,
            spentOutputs: includesUnspentTransactionOutputs ? [outputBeingSpent] : nil
        )
        let messageDigest = OpalCrypto.Hashing.hash256(preimage)
        // Independently double-SHA256 hashed using BCHN's SignatureHash serialization:
        // token prefix, CompactSize(scriptCode.count), scriptCode. SIGHASH_UTXOS
        // still hashes normal output serialization, whose length includes the prefix.
        // https://github.com/bitcoin-cash-node/bitcoin-cash-node/blob/07576013c91ff4a3a74acd85f189c69121cdad1b/src/script/interpreter.cpp#L2522-L2538
        let expectedDigest = try Data(hexadecimalString: expectedDigestHex)
        
        #expect(messageDigest == expectedDigest)
    }
    
    @Test("signature hash for non-token output is unchanged")
    func signatureHashForNonTokenOutputIsUnchanged() throws {
        let lockingScript = try makeLockingScript()
        let transaction = makeTransaction(lockingScript: lockingScript)
        let outputBeingSpent = OpalBase.Transaction.Output(value: 10_000,
                                                  lockingScript: lockingScript,
                                                  tokenData: nil)
        let preimage = try transaction.generatePreimage(for: 0,
                                                        hashType: .makeAll(),
                                                        outputBeingSpent: outputBeingSpent)
        let messageDigest = OpalCrypto.Hashing.hash256(preimage)
        let expectedDigest = try Data(hexadecimalString: "e62ddb675df41732686246b8f0f9f7415da321b4a9e5a4e9d5057551a32594b7")
        
        #expect(messageDigest == expectedDigest)
    }
    
    private func makeTransaction(lockingScript: Data) -> OpalBase.Transaction {
        let previousTransactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x11, count: 32))
        let input = OpalBase.Transaction.Input(previousTransactionHash: previousTransactionHash,
                                      previousTransactionOutputIndex: 0,
                                      unlockingScript: Data(),
                                      sequence: 0xffffffff)
        let output = OpalBase.Transaction.Output(value: 9_000, lockingScript: lockingScript)
        return OpalBase.Transaction(version: 2, inputs: [input], outputs: [output], lockTime: 0)
    }
    
    private func makeLockingScript() throws -> Data {
        let lockingScriptHexadecimal = "76a914" + String(repeating: "22", count: 20) + "88ac"
        return try Data(hexadecimalString: lockingScriptHexadecimal)
    }
    
    private func makeTokenData() throws -> OpalBase.CashTokens.TokenData {
        let fixture = try #require(TokenPrefixTestData.validVectors.first)
        return try makeTokenData(from: fixture.data)
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
}
