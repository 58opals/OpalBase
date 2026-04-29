// SnapshotPersistenceValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("Snapshot encoding and decoding", .tags(.unit))
struct SnapshotPersistenceValidator {
    @Test("address book snapshot encodes token fields")
    func addressBookSnapshotEncodesTokenFields() async throws {
        let storage = try OpalBase.Storage()
        let tokenData = try makeTokenDataWithNonFungibleToken()
        let tokenCategory = tokenData.category.hexForDisplay
        let tokenAmount = tokenData.amount
        let nonFungibleToken = tokenData.nft
        let tokenCommitment = nonFungibleToken?.commitment.hexadecimalString
        
        let unspentOutputSnapshot = OpalBase.Address.Book.Snapshot.UTXO(
            value: 500,
            lockingScript: "51",
            tokenCategory: tokenCategory,
            tokenAmount: tokenAmount,
            nftCapability: nonFungibleToken?.capability,
            nftCommitment: tokenCommitment,
            transactionHash: "abcd",
            outputIndex: 1
        )
        let snapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: .init(),
            changeEntries: .init(),
            utxos: [unspentOutputSnapshot],
            transactions: .init()
        )
        
        let data = try await storage.encodeSnapshot(snapshot)
        let decoded = try await storage.decodeSnapshot(OpalBase.Address.Book.Snapshot.self, from: data)
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
    
    @Test("address book snapshot decodes without token fields")
    func addressBookSnapshotDecodesWithoutTokenFields() async throws {
        let storage = try OpalBase.Storage()
        let snapshotJSON = """
        {"receivingEntries":[],"changeEntries":[],"utxos":[{"value":1000,"lockingScript":"51","transactionHash":"abcd","outputIndex":0}],"transactions":[]}
        """
        let data = Data(snapshotJSON.utf8)
        
        let decoded = try await storage.decodeSnapshot(OpalBase.Address.Book.Snapshot.self, from: data)
        let decodedUnspentOutput = try #require(decoded.utxos.first)
        
        #expect(decodedUnspentOutput.tokenCategory == nil)
        #expect(decodedUnspentOutput.tokenAmount == nil)
        #expect(decodedUnspentOutput.nftCapability == nil)
        #expect(decodedUnspentOutput.nftCommitment == nil)
        #expect(try decodedUnspentOutput.makeTokenData() == nil)
    }

    @Test("address book restore replaces omitted entries and normalizes empty usages")
    func addressBookRestoreReplacesOmittedEntriesAndNormalizesEmptyUsages() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let receivingEntry = try #require(await book.listEntries(for: .receiving).first)
        let changeEntry = try #require(await book.listEntries(for: .change).first)

        try await book.mark(address: receivingEntry.address, isUsed: true)
        try await book.mark(address: changeEntry.address, isUsed: true)

        #expect(await book.countEntries(for: .receiving) == 21)
        #expect(await book.countEntries(for: .change) == 21)

        let emptySnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: [],
            changeEntries: [],
            utxos: [],
            transactions: []
        )

        try await book.refresh(with: emptySnapshot)

        let restoredReceivingEntries = await book.listEntries(for: .receiving)
        let restoredChangeEntries = await book.listEntries(for: .change)

        #expect(restoredReceivingEntries.count == 20)
        #expect(restoredChangeEntries.count == 20)
        #expect(await book.countUnusedEntries(for: .receiving) == 20)
        #expect(await book.countUnusedEntries(for: .change) == 20)
        #expect(restoredReceivingEntries.first?.derivationPath.index == 0)
        #expect(restoredReceivingEntries.last?.derivationPath.index == 19)
        #expect(restoredChangeEntries.first?.derivationPath.index == 0)
        #expect(restoredChangeEntries.last?.derivationPath.index == 19)
        #expect(restoredReceivingEntries.allSatisfy { !$0.isUsed && !$0.isReserved })
        #expect(restoredChangeEntries.allSatisfy { !$0.isUsed && !$0.isReserved })
    }

    @Test("address book restore keeps existing state when snapshot UTXO is malformed")
    func addressBookRestoreKeepsExistingStateWhenSnapshotUTXOIsMalformed() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let alteredReceivingEntries = snapshot.receivingEntries.map { snapshotEntry in
            OpalBase.Address.Book.Snapshot.Entry(
                usage: snapshotEntry.usage,
                index: snapshotEntry.index,
                isUsed: snapshotEntry.isUsed,
                isReserved: snapshotEntry.isReserved,
                balance: snapshotEntry.index == entry.derivationPath.index ? 9_999 : snapshotEntry.balance,
                lastUpdated: snapshotEntry.lastUpdated
            )
        }
        let malformedUTXO = OpalBase.Address.Book.Snapshot.UTXO(
            value: 500,
            lockingScript: "not-hex",
            tokenCategory: nil,
            tokenAmount: nil,
            nftCapability: nil,
            nftCommitment: nil,
            transactionHash: String(repeating: "1", count: 64),
            outputIndex: 0
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: [malformedUTXO],
            transactions: snapshot.transactions
        )

        await #expect(throws: (any Swift.Error).self) {
            try await book.refresh(with: malformedSnapshot)
        }

        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }
    
    private func makeTokenDataWithNonFungibleToken() throws -> OpalBase.CashTokens.TokenData {
        let fixture = try #require(TokenPrefixTestData.validVectors.first { vector in
            vector.data.nonFungibleToken != nil
        })
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
