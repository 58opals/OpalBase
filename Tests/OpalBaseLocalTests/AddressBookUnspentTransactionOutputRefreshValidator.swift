// AddressBookUnspentTransactionOutputRefreshValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Address.Book UTXO Refresh", .tags(.unit, .address, .cashTokens))
struct AddressBookUnspentTransactionOutputRefreshValidator {
    @Test("refresh stores token data from unspent outputs (explicit usage)")
    func refreshStoresTokenDataFromUnspentOutputs() async throws {
        let book = try await AddressBookCashTokensTestData.makeAddressBook()
        let entry = try await book.selectNextEntry(for: .receiving)

        let tokenData = try AddressBookCashTokensTestData.makeTokenData()
        let utxo = OpalBase.Transaction.Output.Unspent(
            value: 12_345,
            lockingScript: entry.address.lockingScript.data,
            tokenData: tokenData,
            previousTransactionHash: OpalBase.Transaction.Hash(
                naturalOrder: Data(repeating: 0x11, count: 32)
            ),
            previousTransactionOutputIndex: 1
        )

        let reader = AddressReaderClient(unspentByAddress: [entry.address.string: [utxo]])

        let refresh = try await book.refreshUTXOSet(using: reader, usage: .receiving)

        let refreshedOutputs = try #require(refresh.utxosByAddress[entry.address])
        #expect(refreshedOutputs.count == 1)
        #expect(refreshedOutputs.first?.tokenData == tokenData)

        let storedOutputs = await book.listUTXOs(for: entry.address)
        #expect(storedOutputs.count == 1)
        #expect(storedOutputs.first?.tokenData == tokenData)
    }

    @Test("refresh stores token data from unspent outputs (all usages)")
    func refreshStoresTokenDataFromUnspentOutputsWhenUsageIsNil() async throws {
        let book = try await AddressBookCashTokensTestData.makeAddressBook()
        let entry = try await book.selectNextEntry(for: .receiving)

        let tokenData = try AddressBookCashTokensTestData.makeTokenData()
        let utxo = OpalBase.Transaction.Output.Unspent(
            value: 7_000,
            lockingScript: entry.address.lockingScript.data,
            tokenData: tokenData,
            previousTransactionHash: OpalBase.Transaction.Hash(
                naturalOrder: Data(repeating: 0x33, count: 32)
            ),
            previousTransactionOutputIndex: 0
        )

        let reader = AddressReaderClient(unspentByAddress: [entry.address.string: [utxo]])

        let refresh = try await book.refreshUTXOSet(using: reader)

        let refreshedOutputs = try #require(refresh.utxosByAddress[entry.address])
        #expect(refreshedOutputs.count == 1)
        #expect(refreshedOutputs.first?.tokenData == tokenData)

        let storedOutputs = await book.listUTXOs(for: entry.address)
        #expect(storedOutputs.count == 1)
        #expect(storedOutputs.first?.tokenData == tokenData)
    }

    @Test("refresh updates cached address balance")
    func refreshUpdatesCachedAddressBalance() async throws {
        let book = try await AddressBookCashTokensTestData.makeAddressBook()
        let entry = try await book.selectNextEntry(for: .receiving)
        let utxo = OpalBase.Transaction.Output.Unspent(
            value: 9_000,
            lockingScript: entry.address.lockingScript.data,
            previousTransactionHash: OpalBase.Transaction.Hash(
                naturalOrder: Data(repeating: 0x44, count: 32)
            ),
            previousTransactionOutputIndex: 0
        )
        let reader = AddressReaderClient(unspentByAddress: [entry.address.string: [utxo]])

        _ = try await book.refreshUTXOSet(using: reader, usage: .receiving)

        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(9_000))
    }

    @Test("adding the same outpoint replaces address-indexed UTXO metadata")
    func addUTXOReplacesAddressIndexedMetadataForSameOutpoint() async throws {
        let book = try await AddressBookCashTokensTestData.makeAddressBook()
        let entry = try await book.selectNextEntry(for: .receiving)
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x55, count: 32)
        )
        let original = OpalBase.Transaction.Output.Unspent(
            value: 1_000,
            lockingScript: entry.address.lockingScript.data,
            previousTransactionHash: transactionHash,
            previousTransactionOutputIndex: 0
        )
        let replacement = OpalBase.Transaction.Output.Unspent(
            value: 2_000,
            lockingScript: entry.address.lockingScript.data,
            previousTransactionHash: transactionHash,
            previousTransactionOutputIndex: 0
        )

        await book.addUTXO(original)
        await book.addUTXO(replacement)

        let storedOutputs = await book.listUTXOs(for: entry.address)
        #expect(storedOutputs.count == 1)
        #expect(storedOutputs.first?.value == replacement.value)
    }
}
