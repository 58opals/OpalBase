// AddressBookUnspentTransactionOutputRefreshValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Address BookActor UTXOModel Refresh", .tags(.unit, .address, .cashTokens))
struct AddressBookUnspentTransactionOutputRefreshValidator {
    @Test("refresh stores token data from unspent outputs (explicit usage)")
    func refreshStoresTokenDataFromUnspentOutputs() async throws {
        let book = try await AddressBookCashTokensTestData.makeAddressBook()
        let entry = try await book.selectNextEntry(for: .receiving)

        let tokenData = try AddressBookCashTokensTestData.makeTokenData()
        let utxo = OpalBase.Transaction.OutputModel.UnspentModel(
            value: 12_345,
            lockingScript: entry.address.lockingScript.data,
            tokenData: tokenData,
            previousTransactionHash: OpalBase.Transaction.HashModel(
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
        let utxo = OpalBase.Transaction.OutputModel.UnspentModel(
            value: 7_000,
            lockingScript: entry.address.lockingScript.data,
            tokenData: tokenData,
            previousTransactionHash: OpalBase.Transaction.HashModel(
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
}

