import Foundation
import Testing
@testable import OpalBase

@Suite("Wallet.FulcrumAddress", .tags(.unit, .wallet))
struct WalletFulcrumAddressValidator {
    @Test("refreshBalances forwards usage and includeUnconfirmed flags")
    func refreshBalancesForwardsUsageAndIncludeUnconfirmed() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)

        let addressReader = WalletAddressReaderStub(
            balancesByAddress: [
                targetEntry.address.string: .init(confirmed: 1_200, unconfirmed: 300)
            ],
            historyByAddress: [
                targetEntry.address.string: [AccountTestFixtures.makeHistoryEntry(hashByte: 0x10)]
            ]
        )
        let confirmationClient = TransactionConfirmationClientStub()
        let fulcrum = Wallet.FulcrumAddress(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        let refresh = try await fulcrum.refreshBalances(
            for: account,
            usage: .receiving,
            includeUnconfirmedHistory: false
        )

        #expect(Set(refresh.balancesByUsage.keys) == Set([.receiving]))
        let expectedTotal = try Satoshi(1_500)
        #expect(refresh.total == expectedTotal)

        let historyRequests = await addressReader.readHistoryRequests()
        #expect(!historyRequests.isEmpty)
        #expect(historyRequests.allSatisfy { !$0.includeUnconfirmed })

        let receivingAddresses = Set(await account.listEntries(for: .receiving).map { $0.address.string })
        let balanceRequests = await addressReader.readBalanceRequests()
        #expect(!balanceRequests.isEmpty)
        #expect(Set(balanceRequests).isSubset(of: receivingAddresses))
    }

    @Test("refreshTransactionHistory forwards includeUnconfirmed and usage")
    func refreshTransactionHistoryForwardsFlags() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x21)
        let historyEntry = Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: 7,
            fee: 120
        )

        let addressReader = WalletAddressReaderStub(
            historyByAddress: [targetEntry.address.string: [historyEntry]]
        )
        let confirmationClient = TransactionConfirmationClientStub()
        let fulcrum = Wallet.FulcrumAddress(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        let changeSet = try await fulcrum.refreshTransactionHistory(
            for: account,
            usage: .receiving,
            includeUnconfirmed: false
        )

        #expect(changeSet.inserted.count == 1)
        let historyRequests = await addressReader.readHistoryRequests()
        #expect(!historyRequests.isEmpty)
        #expect(historyRequests.allSatisfy { !$0.includeUnconfirmed })

        let receivingAddresses = Set(await account.listEntries(for: .receiving).map { $0.address.string })
        #expect(Set(historyRequests.map(\.address)).isSubset(of: receivingAddresses))
    }

    @Test("updateTransactionConfirmations forwards explicit hashes")
    func updateTransactionConfirmationsForwardsHashes() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x31)
        let historyEntry = Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: 5,
            fee: nil
        )

        let addressReader = WalletAddressReaderStub(
            historyByAddress: [targetEntry.address.string: [historyEntry]]
        )
        let confirmationClient = TransactionConfirmationClientStub(
            statusesByHash: [
                hash: .init(transactionHash: hash, transactionHeight: 10, tipHeight: 20, confirmations: 11)
            ]
        )
        let fulcrum = Wallet.FulcrumAddress(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        _ = try await fulcrum.refreshTransactionHistory(for: account, usage: .receiving, includeUnconfirmed: true)
        let changeSet = try await fulcrum.updateTransactionConfirmations(for: account, transactionHashes: [hash])
        #expect(changeSet.updated.count == 1)

        let requestedHashes = await confirmationClient.readConfirmationStatusRequests()
        #expect(requestedHashes == [hash])
    }

    @Test("refreshTransactionConfirmations updates all tracked transactions")
    func refreshTransactionConfirmationsUsesKnownHistory() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let firstEntry = try await account.reserveNextReceivingEntry()
        let secondEntry = try await account.reserveNextReceivingEntry()
        let hashA = AccountTestFixtures.makeHash(byte: 0x41)
        let hashB = AccountTestFixtures.makeHash(byte: 0x42)

        let addressReader = WalletAddressReaderStub(
            historyByAddress: [
                firstEntry.address.string: [.init(transactionIdentifier: hashA.reverseOrder.hexadecimalString, blockHeight: 3, fee: nil)],
                secondEntry.address.string: [.init(transactionIdentifier: hashB.reverseOrder.hexadecimalString, blockHeight: 4, fee: nil)]
            ]
        )
        let confirmationClient = TransactionConfirmationClientStub(
            statusesByHash: [
                hashA: .init(transactionHash: hashA, transactionHeight: 8, tipHeight: 20, confirmations: 13),
                hashB: .init(transactionHash: hashB, transactionHeight: 9, tipHeight: 20, confirmations: 12)
            ]
        )
        let fulcrum = Wallet.FulcrumAddress(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        _ = try await fulcrum.refreshTransactionHistory(for: account, usage: .receiving, includeUnconfirmed: true)
        let changeSet = try await fulcrum.refreshTransactionConfirmations(for: account)
        #expect(changeSet.updated.count == 2)

        let requestedHashes = Set(await confirmationClient.readConfirmationStatusRequests())
        #expect(requestedHashes == Set([hashA, hashB]))
    }
}
