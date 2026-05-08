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

    @Test("refresh orders UTXOs by displayed transaction hash")
    func refreshOrdersUTXOsByDisplayedTransactionHash() async throws {
        let book = try await AddressBookCashTokensTestData.makeAddressBook()
        let entry = try await book.selectNextEntry(for: .receiving)
        let firstHash = OpalBase.Transaction.Hash(
            naturalOrder: Data([0x01] + Array(repeating: 0x00, count: 31))
        )
        let secondHash = OpalBase.Transaction.Hash(
            naturalOrder: Data([0x00] + Array(repeating: 0x00, count: 30) + [0x02])
        )
        let firstUTXO = OpalBase.Transaction.Output.Unspent(
            value: 9_000,
            lockingScript: entry.address.lockingScript.data,
            previousTransactionHash: firstHash,
            previousTransactionOutputIndex: 0
        )
        let secondUTXO = OpalBase.Transaction.Output.Unspent(
            value: 10_000,
            lockingScript: entry.address.lockingScript.data,
            previousTransactionHash: secondHash,
            previousTransactionOutputIndex: 0
        )
        let reader = AddressReaderClient(unspentByAddress: [entry.address.string: [secondUTXO, firstUTXO]])

        let refresh = try await book.refreshUTXOSet(using: reader, usage: .receiving)
        let refreshedOutputs = try #require(refresh.utxosByAddress[entry.address])

        #expect(firstHash.reverseOrder.lexicographicallyPrecedes(secondHash.reverseOrder))
        #expect(refreshedOutputs.map(\.previousTransactionHash) == [firstHash, secondHash])
        #expect(await book.listUTXOs(for: entry.address).map(\.previousTransactionHash) == [firstHash, secondHash])
    }

    @Test("refresh rejects UTXOs whose locking script does not match the requested address")
    func refreshRejectsMismatchedUTXOLockingScript() async throws {
        let book = try await AddressBookCashTokensTestData.makeAddressBook()
        let entry = try await book.selectNextEntry(for: .receiving)
        let mismatchedUTXO = OpalBase.Transaction.Output.Unspent(
            value: 9_000,
            lockingScript: Data([0x51]),
            previousTransactionHash: OpalBase.Transaction.Hash(
                naturalOrder: Data(repeating: 0x45, count: 32)
            ),
            previousTransactionOutputIndex: 0
        )
        let reader = AddressReaderClient(unspentByAddress: [entry.address.string: [mismatchedUTXO]])

        do {
            _ = try await book.refreshUTXOSet(using: reader, usage: .receiving)
            Issue.record("Expected mismatched UTXO locking script to fail")
        } catch let error as OpalBase.Network.Error {
            #expect(error.reason == .protocolViolation)
            #expect(error.message == "Unspent output locking script does not match requested address")
        }

        #expect(await book.listUTXOs(for: entry.address).isEmpty)
    }

    @Test("refresh rejects duplicate UTXO outpoints from the same response")
    func refreshRejectsDuplicateUTXOOutpointsFromResponse() async throws {
        let book = try await AddressBookCashTokensTestData.makeAddressBook()
        let entry = try await book.selectNextEntry(for: .receiving)
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x46, count: 32)
        )
        let firstUTXO = OpalBase.Transaction.Output.Unspent(
            value: 9_000,
            lockingScript: entry.address.lockingScript.data,
            previousTransactionHash: transactionHash,
            previousTransactionOutputIndex: 0
        )
        let duplicateUTXO = OpalBase.Transaction.Output.Unspent(
            value: 12_000,
            lockingScript: entry.address.lockingScript.data,
            previousTransactionHash: transactionHash,
            previousTransactionOutputIndex: 0
        )
        let reader = AddressReaderClient(unspentByAddress: [entry.address.string: [firstUTXO, duplicateUTXO]])

        do {
            _ = try await book.refreshUTXOSet(using: reader, usage: .receiving)
            Issue.record("Expected duplicate UTXO outpoints to fail")
        } catch let error as OpalBase.Network.Error {
            #expect(error.reason == .protocolViolation)
            #expect(error.message == "Unspent output response contained duplicate outpoints")
        }

        #expect(await book.listUTXOs(for: entry.address).isEmpty)
    }

    @Test("refresh rejects duplicate UTXO outpoints across address responses")
    func refreshRejectsDuplicateUTXOOutpointsAcrossAddressResponses() async throws {
        let book = try await AddressBookCashTokensTestData.makeAddressBook()
        let entries = await book.listEntries(for: .receiving)
        let firstEntry = try #require(entries.first)
        let secondEntry = try #require(entries.dropFirst().first)
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x4d, count: 32)
        )
        let firstUTXO = OpalBase.Transaction.Output.Unspent(
            value: 9_000,
            lockingScript: firstEntry.address.lockingScript.data,
            previousTransactionHash: transactionHash,
            previousTransactionOutputIndex: 0
        )
        let duplicateUTXO = OpalBase.Transaction.Output.Unspent(
            value: 12_000,
            lockingScript: secondEntry.address.lockingScript.data,
            previousTransactionHash: transactionHash,
            previousTransactionOutputIndex: 0
        )
        let reader = AddressReaderClient(
            unspentByAddress: [
                firstEntry.address.string: [firstUTXO],
                secondEntry.address.string: [duplicateUTXO]
            ]
        )

        do {
            _ = try await book.refreshUTXOSet(using: reader, usage: .receiving)
            Issue.record("Expected duplicate UTXO outpoints to fail")
        } catch let error as OpalBase.Network.Error {
            #expect(error.reason == .protocolViolation)
            #expect(error.message == "Unspent output response contained duplicate outpoints")
        }

        #expect(await book.listUTXOs(for: firstEntry.address).isEmpty)
        #expect(await book.listUTXOs(for: secondEntry.address).isEmpty)
    }

    @Test("refresh keeps existing UTXOs when replacement balance exceeds the maximum supply")
    func refreshKeepsExistingUTXOsWhenReplacementBalanceOverflows() async throws {
        let book = try await AddressBookCashTokensTestData.makeAddressBook()
        let entry = try await book.selectNextEntry(for: .receiving)
        let existingUTXO = OpalBase.Transaction.Output.Unspent(
            value: 500,
            lockingScript: entry.address.lockingScript.data,
            previousTransactionHash: OpalBase.Transaction.Hash(
                naturalOrder: Data(repeating: 0x47, count: 32)
            ),
            previousTransactionOutputIndex: 0
        )
        let maximumUTXO = OpalBase.Transaction.Output.Unspent(
            value: OpalBase.Satoshi.maximumSatoshi,
            lockingScript: entry.address.lockingScript.data,
            previousTransactionHash: OpalBase.Transaction.Hash(
                naturalOrder: Data(repeating: 0x48, count: 32)
            ),
            previousTransactionOutputIndex: 0
        )
        let overflowUTXO = OpalBase.Transaction.Output.Unspent(
            value: 1,
            lockingScript: entry.address.lockingScript.data,
            previousTransactionHash: OpalBase.Transaction.Hash(
                naturalOrder: Data(repeating: 0x49, count: 32)
            ),
            previousTransactionOutputIndex: 0
        )
        await book.addUTXO(existingUTXO)
        let reader = AddressReaderClient(unspentByAddress: [entry.address.string: [maximumUTXO, overflowUTXO]])

        await #expect(throws: OpalBase.Satoshi.Error.exceedsMaximumAmount) {
            _ = try await book.refreshUTXOSet(using: reader, usage: .receiving)
        }

        #expect(await book.listUTXOs(for: entry.address) == [existingUTXO])
    }

    @Test("refresh keeps existing UTXOs when aggregate balance exceeds the maximum supply")
    func refreshKeepsExistingUTXOsWhenAggregateBalanceOverflows() async throws {
        let book = try await AddressBookCashTokensTestData.makeAddressBook()
        let entries = await book.listEntries(for: .receiving)
        let firstEntry = try #require(entries.first)
        let secondEntry = try #require(entries.dropFirst().first)
        let existingUTXO = OpalBase.Transaction.Output.Unspent(
            value: 500,
            lockingScript: firstEntry.address.lockingScript.data,
            previousTransactionHash: OpalBase.Transaction.Hash(
                naturalOrder: Data(repeating: 0x4a, count: 32)
            ),
            previousTransactionOutputIndex: 0
        )
        let maximumUTXO = OpalBase.Transaction.Output.Unspent(
            value: OpalBase.Satoshi.maximumSatoshi,
            lockingScript: firstEntry.address.lockingScript.data,
            previousTransactionHash: OpalBase.Transaction.Hash(
                naturalOrder: Data(repeating: 0x4b, count: 32)
            ),
            previousTransactionOutputIndex: 0
        )
        let overflowUTXO = OpalBase.Transaction.Output.Unspent(
            value: 1,
            lockingScript: secondEntry.address.lockingScript.data,
            previousTransactionHash: OpalBase.Transaction.Hash(
                naturalOrder: Data(repeating: 0x4c, count: 32)
            ),
            previousTransactionOutputIndex: 0
        )
        await book.addUTXO(existingUTXO)
        let reader = AddressReaderClient(
            unspentByAddress: [
                firstEntry.address.string: [maximumUTXO],
                secondEntry.address.string: [overflowUTXO]
            ]
        )

        await #expect(throws: OpalBase.Satoshi.Error.exceedsMaximumAmount) {
            _ = try await book.refreshUTXOSet(using: reader, usage: .receiving)
        }

        #expect(await book.listUTXOs(for: firstEntry.address) == [existingUTXO])
        #expect(await book.listUTXOs(for: secondEntry.address).isEmpty)
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

    @Test("address replacement moves same outpoint between address indexes")
    func addressReplacementMovesSameOutpointBetweenAddressIndexes() async throws {
        let book = try await AddressBookCashTokensTestData.makeAddressBook()
        let entries = await book.listEntries(for: .receiving)
        let firstEntry = try #require(entries.first)
        let secondEntry = try #require(entries.dropFirst().first)
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: Data(repeating: 0x56, count: 32)
        )
        let original = OpalBase.Transaction.Output.Unspent(
            value: 1_000,
            lockingScript: firstEntry.address.lockingScript.data,
            previousTransactionHash: transactionHash,
            previousTransactionOutputIndex: 0
        )
        let moved = OpalBase.Transaction.Output.Unspent(
            value: 2_000,
            lockingScript: secondEntry.address.lockingScript.data,
            previousTransactionHash: transactionHash,
            previousTransactionOutputIndex: 0
        )

        await book.addUTXO(original)
        await book.replaceUTXOs(for: secondEntry.address, withValidated: [moved])

        #expect(await book.listUTXOs(for: firstEntry.address).isEmpty)
        #expect(await book.listUTXOs(for: secondEntry.address) == [moved])
        #expect(await book.listUTXOs() == [moved])
    }
}
