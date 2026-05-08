// TransactionOutputOrderValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Transaction output ordering", .tags(.unit, .transaction))
struct TransactionOutputOrderValidator {
    @Test("applyBIP69Ordering sorts token presence after locking script bytes")
    func applyBIP69OrderingSortsTokenPresence() throws {
        let lockingScript = Data([0x51])
        let category = try makeCategory(using: 0x01)
        let tokenData = OpalBase.CashTokens.TokenData(category: category, amount: 1, nft: nil)
        let tokenOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: tokenData)
        let plainOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript)
        
        let orderedOutputs = OpalBase.Transaction.Output.applyBIP69Ordering([tokenOutput, plainOutput])
        
        #expect(orderedOutputs == [plainOutput, tokenOutput])
    }
    
    @Test("applyBIP69Ordering sorts token amounts after token presence")
    func applyBIP69OrderingSortsTokenAmount() throws {
        let lockingScript = Data([0x51])
        let category = try makeCategory(using: 0x01)
        let smallerAmount = OpalBase.CashTokens.TokenData(category: category, amount: 1, nft: nil)
        let largerAmount = OpalBase.CashTokens.TokenData(category: category, amount: 2, nft: nil)
        let smallerOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: smallerAmount)
        let largerOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: largerAmount)
        
        let orderedOutputs = OpalBase.Transaction.Output.applyBIP69Ordering([largerOutput, smallerOutput])
        
        #expect(orderedOutputs == [smallerOutput, largerOutput])
    }
    
    @Test("applyBIP69Ordering sorts category before non-fungible token data")
    func applyBIP69OrderingSortsCategoryBeforeNonFungibleTokenData() throws {
        let lockingScript = Data([0x51])
        let smallerCategory = try makeCategory(using: 0x01)
        let largerCategory = try makeCategory(using: 0x02)
        let noneCapability = try OpalBase.CashTokens.NFT(capability: .none, commitment: Data())
        let mintingCapability = try OpalBase.CashTokens.NFT(capability: .minting, commitment: Data())
        let smallerToken = OpalBase.CashTokens.TokenData(category: smallerCategory, amount: 1, nft: mintingCapability)
        let largerToken = OpalBase.CashTokens.TokenData(category: largerCategory, amount: 1, nft: noneCapability)
        let smallerOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: smallerToken)
        let largerOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: largerToken)
        
        let orderedOutputs = OpalBase.Transaction.Output.applyBIP69Ordering([largerOutput, smallerOutput])
        
        #expect(orderedOutputs == [smallerOutput, largerOutput])
    }
    
    @Test("applyBIP69Ordering sorts category before token amount")
    func applyBIP69OrderingSortsCategoryBeforeTokenAmount() throws {
        let lockingScript = Data([0x51])
        let smallerCategory = try makeCategory(using: 0x01)
        let largerCategory = try makeCategory(using: 0x02)
        let baseToken = try OpalBase.CashTokens.NFT(capability: .none, commitment: Data())
        let smallerToken = OpalBase.CashTokens.TokenData(category: smallerCategory, amount: 2, nft: baseToken)
        let largerToken = OpalBase.CashTokens.TokenData(category: largerCategory, amount: 1, nft: baseToken)
        let smallerOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: smallerToken)
        let largerOutput = OpalBase.Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: largerToken)
        
        let orderedOutputs = OpalBase.Transaction.Output.applyBIP69Ordering([largerOutput, smallerOutput])
        
        #expect(orderedOutputs == [smallerOutput, largerOutput])
    }
    
    private func makeCategory(using byte: UInt8) throws -> OpalBase.CashTokens.CategoryID {
        try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: byte, count: 32))
    }
}
