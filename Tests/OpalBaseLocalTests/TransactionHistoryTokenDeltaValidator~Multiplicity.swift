// TransactionHistoryTokenDeltaValidator~Multiplicity.swift

import Foundation
import Testing
@testable import OpalBase

extension TransactionHistoryTokenDeltaValidator {
    @Test("preserves duplicate non-fungible token additions")
    func preserveDuplicateNonFungibleTokenAdditions() async throws {
        let book = try await makeAddressBook()
        let receivingEntry = try #require(await book.listEntries(for: .receiving).first)
        let tokenData = try makeRepeatedNonFungibleTokenData()
        let output = OpalBase.Transaction.Output(
            value: 546,
            lockingScript: receivingEntry.address.lockingScript.data,
            tokenData: tokenData
        )
        let transaction = OpalBase.Transaction(
            version: 2,
            inputs: [],
            outputs: [output, output],
            lockTime: 0
        )
        let transactionReader = OpalBase.Network.TransactionReader(
            TransactionReaderClient(rawTransactionsByHash: [:])
        )

        let tokenDelta = try await book.makeTokenDelta(
            from: transaction,
            transactionReader: transactionReader,
            walletScriptHashes: [receivingEntry.address.makeScriptHash().hexadecimalString]
        )
        let canonicalTokenData = OpalBase.CashTokens.TokenData(
            category: tokenData.category,
            amount: nil,
            nft: tokenData.nft
        )

        #expect(tokenDelta.nonFungibleTokenAdditions == [
            canonicalTokenData,
            canonicalTokenData
        ])
        #expect(tokenDelta.nonFungibleTokenRemovals.isEmpty)
    }

    @Test("nets duplicate non-fungible tokens by count")
    func netDuplicateNonFungibleTokensByCount() async throws {
        let book = try await makeAddressBook()
        let receivingEntry = try #require(await book.listEntries(for: .receiving).first)
        let tokenData = try makeRepeatedNonFungibleTokenData()
        let fundingInput = OpalBase.Transaction.Input(
            previousTransactionHash: OpalBase.Transaction.Hash(
                naturalOrder: Data(repeating: 0x00, count: 32)
            ),
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let previousTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [fundingInput],
            outputs: [
                .init(
                    value: 546,
                    lockingScript: receivingEntry.address.lockingScript.data,
                    tokenData: tokenData
                )
            ],
            lockTime: 0
        )
        let previousRawTransaction = try previousTransaction.encode()
        let previousHash = Self.hash(for: previousRawTransaction)
        let currentInput = OpalBase.Transaction.Input(
            previousTransactionHash: previousHash,
            previousTransactionOutputIndex: 0,
            unlockingScript: Data()
        )
        let output = OpalBase.Transaction.Output(
            value: 546,
            lockingScript: receivingEntry.address.lockingScript.data,
            tokenData: tokenData
        )
        let currentTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [currentInput],
            outputs: [output, output],
            lockTime: 0
        )
        let transactionReader = OpalBase.Network.TransactionReader(
            TransactionReaderClient(rawTransactionsByHash: [
                previousHash: previousRawTransaction
            ])
        )

        let tokenDelta = try await book.makeTokenDelta(
            from: currentTransaction,
            transactionReader: transactionReader,
            walletScriptHashes: [receivingEntry.address.makeScriptHash().hexadecimalString]
        )
        let canonicalTokenData = OpalBase.CashTokens.TokenData(
            category: tokenData.category,
            amount: nil,
            nft: tokenData.nft
        )

        #expect(tokenDelta.nonFungibleTokenAdditions == [canonicalTokenData])
        #expect(tokenDelta.nonFungibleTokenRemovals.isEmpty)
    }

    private func makeRepeatedNonFungibleTokenData() throws -> OpalBase.CashTokens.TokenData {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x52, count: 32)
        )
        let nonFungibleToken = try OpalBase.CashTokens.NFT(
            capability: .none,
            commitment: Data([0x01, 0x02])
        )
        return OpalBase.CashTokens.TokenData(
            category: category,
            amount: 7,
            nft: nonFungibleToken
        )
    }
}
