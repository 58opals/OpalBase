import Foundation
import Testing
@testable import OpalBase

@Suite("Transaction Output Ordering", .tags(.unit, .transaction))
struct TransactionOutputOrderTests {
    @Test("applyBIP69Ordering sorts token presence after locking script bytes")
    func testApplyBIP69OrderingSortsTokenPresence() throws {
        let lockingScript = Data([0x51])
        let category = try makeCategory(using: 0x01)
        let tokenData = CashTokens.TokenData(category: category, amount: 1, nft: nil)
        let tokenOutput = Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: tokenData)
        let plainOutput = Transaction.Output(value: 1_000, lockingScript: lockingScript)
        
        let orderedOutputs = Transaction.Output.applyBIP69Ordering([tokenOutput, plainOutput])
        
        #expect(orderedOutputs == [plainOutput, tokenOutput])
    }
    
    @Test("applyBIP69Ordering sorts token amounts after token presence")
    func testApplyBIP69OrderingSortsTokenAmount() throws {
        let lockingScript = Data([0x51])
        let category = try makeCategory(using: 0x01)
        let smallerAmount = CashTokens.TokenData(category: category, amount: 1, nft: nil)
        let largerAmount = CashTokens.TokenData(category: category, amount: 2, nft: nil)
        let smallerOutput = Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: smallerAmount)
        let largerOutput = Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: largerAmount)
        
        let orderedOutputs = Transaction.Output.applyBIP69Ordering([largerOutput, smallerOutput])
        
        #expect(orderedOutputs == [smallerOutput, largerOutput])
    }
    
    @Test("applyBIP69Ordering sorts non-fungible token data before category")
    func testApplyBIP69OrderingSortsNonFungibleTokenData() throws {
        let lockingScript = Data([0x51])
        let category = try makeCategory(using: 0x01)
        let noneCapability = try CashTokens.NFT(capability: .none, commitment: Data())
        let mintingCapability = try CashTokens.NFT(capability: .minting, commitment: Data())
        let smallerToken = CashTokens.TokenData(category: category, amount: 1, nft: noneCapability)
        let largerToken = CashTokens.TokenData(category: category, amount: 1, nft: mintingCapability)
        let smallerOutput = Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: smallerToken)
        let largerOutput = Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: largerToken)
        
        let orderedOutputs = Transaction.Output.applyBIP69Ordering([largerOutput, smallerOutput])
        
        #expect(orderedOutputs == [smallerOutput, largerOutput])
    }
    
    @Test("applyBIP69Ordering sorts category order after token metadata")
    func testApplyBIP69OrderingSortsCategoryOrder() throws {
        let lockingScript = Data([0x51])
        let smallerCategory = try makeCategory(using: 0x01)
        let largerCategory = try makeCategory(using: 0x02)
        let baseToken = try CashTokens.NFT(capability: .none, commitment: Data())
        let smallerToken = CashTokens.TokenData(category: smallerCategory, amount: 1, nft: baseToken)
        let largerToken = CashTokens.TokenData(category: largerCategory, amount: 1, nft: baseToken)
        let smallerOutput = Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: smallerToken)
        let largerOutput = Transaction.Output(value: 1_000, lockingScript: lockingScript, tokenData: largerToken)
        
        let orderedOutputs = Transaction.Output.applyBIP69Ordering([largerOutput, smallerOutput])
        
        #expect(orderedOutputs == [smallerOutput, largerOutput])
    }
    
    private func makeCategory(using byte: UInt8) throws -> CashTokens.CategoryID {
        try CashTokens.CategoryID(transactionOrderData: Data(repeating: byte, count: 32))
    }
}
