import Foundation
import Testing
@testable import OpalBase

@Suite("Snapshot encoding and decoding")
struct SnapshotPersistenceTests {
    @MainActor @Test("address book snapshot encodes token fields")
    func addressBookSnapshotEncodesTokenFields() throws {
        let storage = try Storage()
        let tokenData = try makeTokenDataWithNonFungibleToken()
        let tokenCategory = tokenData.category.hexForDisplay
        let tokenAmount = tokenData.amount
        let nonFungibleToken = tokenData.nft
        let tokenCommitment = nonFungibleToken?.commitment.hexadecimalString
        
        let unspentOutputSnapshot = Address.Book.Snapshot.UTXO(
            value: 500,
            lockingScript: "51",
            tokenCategory: tokenCategory,
            tokenAmount: tokenAmount,
            nftCapability: nonFungibleToken?.capability,
            nftCommitment: tokenCommitment,
            transactionHash: "abcd",
            outputIndex: 1
        )
        let snapshot = Address.Book.Snapshot(
            receivingEntries: .init(),
            changeEntries: .init(),
            utxos: [unspentOutputSnapshot],
            transactions: .init()
        )
        
        let data = try storage.encodeSnapshot(snapshot)
        let decoded = try storage.decodeSnapshot(Address.Book.Snapshot.self, from: data)
        let decodedUnspentOutput = try #require(decoded.utxos.first)
        
        #expect(decodedUnspentOutput.tokenCategory == tokenCategory)
        #expect(decodedUnspentOutput.tokenAmount == tokenAmount)
        #expect(decodedUnspentOutput.nftCapability == nonFungibleToken?.capability)
        #expect(decodedUnspentOutput.nftCommitment == tokenCommitment)
        
        let decodedTokenData = try decodedUnspentOutput.makeTokenData()
        #expect(decodedTokenData?.category.hexForDisplay == tokenCategory)
        #expect(decodedTokenData?.amount == tokenAmount)
        #expect(decodedTokenData?.nft?.capability == nonFungibleToken?.capability)
        #expect(decodedTokenData?.nft?.commitment == nonFungibleToken?.commitment)
    }
    
    @MainActor @Test("address book snapshot decodes without token fields")
    func addressBookSnapshotDecodesWithoutTokenFields() throws {
        let storage = try Storage()
        let snapshotJSON = """
        {"receivingEntries":[],"changeEntries":[],"utxos":[{"value":1000,"lockingScript":"51","transactionHash":"abcd","outputIndex":0}],"transactions":[]}
        """
        let data = Data(snapshotJSON.utf8)
        
        let decoded = try storage.decodeSnapshot(Address.Book.Snapshot.self, from: data)
        let decodedUnspentOutput = try #require(decoded.utxos.first)
        
        #expect(decodedUnspentOutput.tokenCategory == nil)
        #expect(decodedUnspentOutput.tokenAmount == nil)
        #expect(decodedUnspentOutput.nftCapability == nil)
        #expect(decodedUnspentOutput.nftCommitment == nil)
        #expect(try decodedUnspentOutput.makeTokenData() == nil)
    }
    
    private func makeTokenDataWithNonFungibleToken() throws -> CashTokens.TokenData {
        let fixture = try #require(TokenPrefixFixtureStore.validVectors.first { vector in
            vector.data.nonFungibleToken != nil
        })
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
