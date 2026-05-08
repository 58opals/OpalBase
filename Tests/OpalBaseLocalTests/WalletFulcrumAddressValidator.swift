// WalletFulcrumAddressValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Wallet.Fulcrum", .tags(.unit, .wallet))
struct WalletFulcrumAddressValidator {
    @Test("refreshBalances forwards usage and includeUnconfirmed flags")
    func refreshBalancesForwardsUsageAndIncludeUnconfirmed() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)

        let addressReader = WalletAddressReaderTestActor(
            balancesByAddress: [
                targetEntry.address.string: .init(confirmed: 1_200, unconfirmed: 300)
            ],
            historyByAddress: [
                targetEntry.address.string: [AccountTestFixtures.makeHistoryEntry(hashByte: 0x10)]
            ]
        )
        let confirmationClient = TransactionConfirmationClientTestActor()
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        let refresh = try await fulcrum.refreshBalances(
            for: account,
            usage: .receiving,
            includeUnconfirmedHistory: false
        )

        #expect(Set(refresh.balancesByUsage.keys) == Set([.receiving]))
        let expectedTotal = try OpalBase.Satoshi(1_500)
        #expect(refresh.total == expectedTotal)

        let historyRequests = await addressReader.readHistoryRequests()
        #expect(!historyRequests.isEmpty)
        #expect(historyRequests.allSatisfy { !$0.includeUnconfirmed })

        let receivingAddresses = Set(await account.listEntries(for: .receiving).map { $0.address.string })
        let balanceRequests = await addressReader.readBalanceRequests()
        #expect(!balanceRequests.isEmpty)
        #expect(Set(balanceRequests).isSubset(of: receivingAddresses))
    }

    @Test("refreshBalances subtracts negative unconfirmed deltas")
    func refreshBalancesSubtractsNegativeUnconfirmedDeltas() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)

        let addressReader = WalletAddressReaderTestActor(
            balancesByAddress: [
                targetEntry.address.string: .init(confirmed: 1_200, unconfirmed: -300)
            ],
            historyByAddress: [
                targetEntry.address.string: [AccountTestFixtures.makeHistoryEntry(hashByte: 0x11)]
            ]
        )
        let confirmationClient = TransactionConfirmationClientTestActor()
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        let refresh = try await fulcrum.refreshBalances(
            for: account,
            usage: .receiving,
            includeUnconfirmedHistory: false
        )

        let expectedTotal = try OpalBase.Satoshi(900)
        #expect(refresh.total == expectedTotal)
    }

    @Test("refreshBalances rejects negative unconfirmed deltas below zero")
    func refreshBalancesRejectsNegativeUnconfirmedUnderflow() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)

        let addressReader = WalletAddressReaderTestActor(
            balancesByAddress: [
                targetEntry.address.string: .init(confirmed: 1_200, unconfirmed: -1_500)
            ],
            historyByAddress: [
                targetEntry.address.string: [AccountTestFixtures.makeHistoryEntry(hashByte: 0x12)]
            ]
        )
        let confirmationClient = TransactionConfirmationClientTestActor()
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        await #expect(
            throws: OpalBase.Account.Error.balanceRefreshFailed(
                targetEntry.address,
                OpalBase.Satoshi.Error.negativeResult
            )
        ) {
            _ = try await fulcrum.refreshBalances(
                for: account,
                usage: .receiving,
                includeUnconfirmedHistory: false
            )
        }
    }
    
    @Test("refreshBalances leaves cache unchanged when a later usage fails")
    func refreshBalancesLeavesCacheUnchangedWhenLaterUsageFails() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let addressBook = await account.addressBook
        let receivingEntry = try await addressBook.selectNextEntry(for: .receiving)
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        
        do {
            _ = try await account.refreshBalances { address in
                if address == receivingEntry.address {
                    return try OpalBase.Satoshi(1_200)
                }
                if address == changeEntry.address {
                    throw BalanceRefreshTestFailure.rejected
                }
                return OpalBase.Satoshi()
            }
            Issue.record("Expected refreshBalances to fail when a later usage loader fails")
        } catch let error as OpalBase.Account.Error {
            guard case .balanceRefreshFailed(let address, _) = error else {
                Issue.record("Unexpected account error: \(error)")
                return
            }
            #expect(address == changeEntry.address)
        }
        
        #expect(try await addressBook.readCachedBalance(for: receivingEntry.address) == nil)
    }

    @Test("refreshTransactionHistory forwards includeUnconfirmed and usage")
    func refreshTransactionHistoryForwardsFlags() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x21)
        let historyEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: 7,
            fee: 120
        )

        let addressReader = WalletAddressReaderTestActor(
            historyByAddress: [targetEntry.address.string: [historyEntry]]
        )
        let confirmationClient = TransactionConfirmationClientTestActor()
        let fulcrum = OpalBase.Wallet.Fulcrum(
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

    @Test("refreshTransactionHistory rejects unconfirmed entries in confirmed-only results")
    func refreshTransactionHistoryRejectsUnconfirmedEntriesWhenExcluded() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x36)
        let historyEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: -1,
            fee: nil
        )
        let addressReader = WalletAddressReaderTestActor(
            historyByAddress: [targetEntry.address.string: [historyEntry]]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: TransactionConfirmationClientTestActor()
        )

        do {
            _ = try await fulcrum.refreshTransactionHistory(
                for: account,
                usage: .receiving,
                includeUnconfirmed: false
            )
            Issue.record("Expected confirmed-only history refresh to reject unconfirmed entries")
        } catch let error as OpalBase.Account.Error {
            guard case .transactionHistoryRefreshFailed(let address, let underlying) = error else {
                Issue.record("Unexpected account error: \(error)")
                return
            }
            #expect(address == targetEntry.address)
            let networkError = try #require(underlying as? OpalBase.Network.Error)
            #expect(networkError.reason == .protocolViolation)
            #expect(networkError.message == "Confirmed-only history response included an unconfirmed transaction")
        }

        #expect(await account.loadTransactionHistory().isEmpty)
    }

    @Test("refreshTransactionHistory rejects duplicate transaction identifiers in one response")
    func refreshTransactionHistoryRejectsDuplicateTransactionIdentifiers() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x38)
        let firstEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: -1,
            fee: nil
        )
        let duplicateEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: 7,
            fee: nil
        )
        let addressReader = WalletAddressReaderTestActor(
            historyByAddress: [targetEntry.address.string: [firstEntry, duplicateEntry]]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: TransactionConfirmationClientTestActor()
        )

        do {
            _ = try await fulcrum.refreshTransactionHistory(
                for: account,
                usage: .receiving,
                includeUnconfirmed: true
            )
            Issue.record("Expected duplicate transaction identifiers to fail")
        } catch let error as OpalBase.Account.Error {
            guard case .transactionHistoryRefreshFailed(let address, let underlying) = error else {
                Issue.record("Unexpected account error: \(error)")
                return
            }
            #expect(address == targetEntry.address)
            let networkError = try #require(underlying as? OpalBase.Network.Error)
            #expect(networkError.reason == .protocolViolation)
            #expect(networkError.message == "History response contained duplicate transaction identifiers")
        }

        #expect(await account.loadTransactionHistory().isEmpty)
    }

    @Test("refreshTransactionHistory rejects conflicting heights across wallet addresses")
    func refreshTransactionHistoryRejectsConflictingHeightsAcrossWalletAddresses() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let firstEntry = try await account.reserveNextReceivingEntry()
        let secondEntry = try await account.reserveNextReceivingEntry()
        let hash = AccountTestFixtures.makeHash(byte: 0x39)
        let unconfirmedEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: -1,
            fee: nil
        )
        let confirmedEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: 7,
            fee: nil
        )
        let addressReader = WalletAddressReaderTestActor(
            historyByAddress: [
                firstEntry.address.string: [unconfirmedEntry],
                secondEntry.address.string: [confirmedEntry]
            ]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: TransactionConfirmationClientTestActor()
        )

        do {
            _ = try await fulcrum.refreshTransactionHistory(
                for: account,
                usage: .receiving,
                includeUnconfirmed: true
            )
            Issue.record("Expected conflicting cross-address history heights to fail")
        } catch let error as OpalBase.Account.Error {
            guard case .transactionHistoryRefreshFailed(_, let underlying) = error else {
                Issue.record("Unexpected account error: \(error)")
                return
            }
            let networkError = try #require(underlying as? OpalBase.Network.Error)
            #expect(networkError.reason == .protocolViolation)
            #expect(networkError.message == "History response contained conflicting transaction heights")
        }

        #expect(await account.loadTransactionHistory().isEmpty)
    }

    @Test("refreshTransactionHistory rejects conflicting fees across wallet addresses")
    func refreshTransactionHistoryRejectsConflictingFeesAcrossWalletAddresses() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let firstEntry = try await account.reserveNextReceivingEntry()
        let secondEntry = try await account.reserveNextReceivingEntry()
        let hash = AccountTestFixtures.makeHash(byte: 0x3A)
        let firstHistoryEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: 7,
            fee: 100
        )
        let secondHistoryEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: 7,
            fee: 200
        )
        let addressReader = WalletAddressReaderTestActor(
            historyByAddress: [
                firstEntry.address.string: [firstHistoryEntry],
                secondEntry.address.string: [secondHistoryEntry]
            ]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: TransactionConfirmationClientTestActor()
        )

        do {
            _ = try await fulcrum.refreshTransactionHistory(
                for: account,
                usage: .receiving,
                includeUnconfirmed: true
            )
            Issue.record("Expected conflicting cross-address history fees to fail")
        } catch let error as OpalBase.Account.Error {
            guard case .transactionHistoryRefreshFailed(_, let underlying) = error else {
                Issue.record("Unexpected account error: \(error)")
                return
            }
            let networkError = try #require(underlying as? OpalBase.Network.Error)
            #expect(networkError.reason == .protocolViolation)
            #expect(networkError.message == "History response contained conflicting transaction fees")
        }

        #expect(await account.loadTransactionHistory().isEmpty)
    }

    @Test("refreshTransactionHistory rejects conflicting heights across usages")
    func refreshTransactionHistoryRejectsConflictingHeightsAcrossUsages() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let receivingEntry = try await account.reserveNextReceivingEntry()
        let changeEntry = try await account.selectNextEntry(for: .change)
        let hash = AccountTestFixtures.makeHash(byte: 0x3B)
        let unconfirmedEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: -1,
            fee: nil
        )
        let confirmedEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: 7,
            fee: nil
        )
        let addressReader = WalletAddressReaderTestActor(
            historyByAddress: [
                receivingEntry.address.string: [unconfirmedEntry],
                changeEntry.address.string: [confirmedEntry]
            ]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: TransactionConfirmationClientTestActor()
        )

        do {
            _ = try await fulcrum.refreshTransactionHistory(
                for: account,
                usage: nil,
                includeUnconfirmed: true
            )
            Issue.record("Expected conflicting cross-usage history heights to fail")
        } catch let error as OpalBase.Account.Error {
            guard case .transactionHistoryRefreshFailed(_, let underlying) = error else {
                Issue.record("Unexpected account error: \(error)")
                return
            }
            let networkError = try #require(underlying as? OpalBase.Network.Error)
            #expect(networkError.reason == .protocolViolation)
            #expect(networkError.message == "History response contained conflicting transaction heights")
        }

        #expect(await account.loadTransactionHistory().isEmpty)
    }

    @Test("updateTransactionConfirmations forwards explicit hashes")
    func updateTransactionConfirmationsForwardsHashes() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x31)
        let historyEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: 5,
            fee: nil
        )

        let addressReader = WalletAddressReaderTestActor(
            historyByAddress: [targetEntry.address.string: [historyEntry]]
        )
        let confirmationClient = TransactionConfirmationClientTestActor(
            statusesByHash: [
                hash: .init(transactionHash: hash, transactionHeight: 10, tipHeight: 20, confirmations: 11)
            ]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        _ = try await fulcrum.refreshTransactionHistory(for: account, usage: .receiving, includeUnconfirmed: true)
        let changeSet = try await fulcrum.updateTransactionConfirmations(for: account, transactionHashes: [hash])
        #expect(changeSet.updated.count == 1)

        let requestedHashes = await confirmationClient.readConfirmationStatusRequests()
        #expect(requestedHashes == [hash])
    }

    @Test("updateTransactionConfirmations rejects mismatched status hashes")
    func updateTransactionConfirmationsRejectsMismatchedStatusHashes() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let requestedHash = AccountTestFixtures.makeHash(byte: 0x32)
        let mismatchedHash = AccountTestFixtures.makeHash(byte: 0x33)
        let historyEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: requestedHash.reverseOrder.hexadecimalString,
            blockHeight: -1,
            fee: nil
        )

        let addressReader = WalletAddressReaderTestActor(
            historyByAddress: [targetEntry.address.string: [historyEntry]]
        )
        let confirmationClient = TransactionConfirmationClientTestActor(
            statusesByHash: [
                requestedHash: .init(
                    transactionHash: mismatchedHash,
                    transactionHeight: 10,
                    tipHeight: 20,
                    confirmations: 11
                )
            ]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        _ = try await fulcrum.refreshTransactionHistory(for: account, usage: .receiving, includeUnconfirmed: true)

        do {
            _ = try await fulcrum.updateTransactionConfirmations(
                for: account,
                transactionHashes: [requestedHash]
            )
            Issue.record("Expected mismatched confirmation status to fail")
        } catch let error as OpalBase.Account.Error {
            guard case .transactionConfirmationRefreshFailed(let hash, let underlying) = error else {
                Issue.record("Unexpected account error: \(error)")
                return
            }
            #expect(hash == requestedHash)
            let networkError = try #require(underlying as? OpalBase.Network.Error)
            #expect(networkError.reason == .protocolViolation)
            #expect(networkError.message == "Confirmation status hash mismatch")
        }

        let record = try #require(await account.loadTransactionHistory().first { $0.transactionHash == requestedHash })
        #expect(record.status == .discovered)
        #expect(record.confirmationMetadata.height == nil)
    }

    @Test("updateTransactionConfirmations rejects heights above the reported tip")
    func updateTransactionConfirmationsRejectsHeightsAboveTip() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x34)
        let historyEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: -1,
            fee: nil
        )

        let addressReader = WalletAddressReaderTestActor(
            historyByAddress: [targetEntry.address.string: [historyEntry]]
        )
        let confirmationClient = TransactionConfirmationClientTestActor(
            statusesByHash: [
                hash: .init(
                    transactionHash: hash,
                    transactionHeight: 30,
                    tipHeight: 20,
                    confirmations: nil
                )
            ]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        _ = try await fulcrum.refreshTransactionHistory(for: account, usage: .receiving, includeUnconfirmed: true)

        do {
            _ = try await fulcrum.updateTransactionConfirmations(
                for: account,
                transactionHashes: [hash]
            )
            Issue.record("Expected future-height confirmation status to fail")
        } catch let error as OpalBase.Account.Error {
            guard case .transactionConfirmationRefreshFailed(let failedHash, let underlying) = error else {
                Issue.record("Unexpected account error: \(error)")
                return
            }
            #expect(failedHash == hash)
            let networkError = try #require(underlying as? OpalBase.Network.Error)
            #expect(networkError.reason == .protocolViolation)
            #expect(networkError.message == "Confirmation status height exceeds tip height")
        }

        let record = try #require(await account.loadTransactionHistory().first { $0.transactionHash == hash })
        #expect(record.status == .discovered)
        #expect(record.confirmationMetadata.height == nil)
    }

    @Test("updateTransactionConfirmations rejects positive confirmations without height")
    func updateTransactionConfirmationsRejectsConfirmationsWithoutHeight() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x35)
        let historyEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: -1,
            fee: nil
        )

        let addressReader = WalletAddressReaderTestActor(
            historyByAddress: [targetEntry.address.string: [historyEntry]]
        )
        let confirmationClient = TransactionConfirmationClientTestActor(
            statusesByHash: [
                hash: .init(
                    transactionHash: hash,
                    transactionHeight: nil,
                    tipHeight: 20,
                    confirmations: 2
                )
            ]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        _ = try await fulcrum.refreshTransactionHistory(for: account, usage: .receiving, includeUnconfirmed: true)

        do {
            _ = try await fulcrum.updateTransactionConfirmations(
                for: account,
                transactionHashes: [hash]
            )
            Issue.record("Expected confirmation count without height to fail")
        } catch let error as OpalBase.Account.Error {
            guard case .transactionConfirmationRefreshFailed(let failedHash, let underlying) = error else {
                Issue.record("Unexpected account error: \(error)")
                return
            }
            #expect(failedHash == hash)
            let networkError = try #require(underlying as? OpalBase.Network.Error)
            #expect(networkError.reason == .protocolViolation)
            #expect(networkError.message == "Confirmation count requires a confirmed transaction height")
        }

        let record = try #require(await account.loadTransactionHistory().first { $0.transactionHash == hash })
        #expect(record.status == .discovered)
        #expect(record.confirmationMetadata.height == nil)
    }

    @Test("updateTransactionConfirmations rejects confirmation counts that do not match height and tip")
    func updateTransactionConfirmationsRejectsMismatchedConfirmationCounts() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let targetEntry = try await account.selectNextEntry(for: .receiving)
        let hash = AccountTestFixtures.makeHash(byte: 0x37)
        let historyEntry = OpalBase.Network.TransactionHistoryEntry(
            transactionIdentifier: hash.reverseOrder.hexadecimalString,
            blockHeight: -1,
            fee: nil
        )

        let addressReader = WalletAddressReaderTestActor(
            historyByAddress: [targetEntry.address.string: [historyEntry]]
        )
        let confirmationClient = TransactionConfirmationClientTestActor(
            statusesByHash: [
                hash: .init(
                    transactionHash: hash,
                    transactionHeight: 10,
                    tipHeight: 20,
                    confirmations: 1
                )
            ]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: addressReader,
            transactionHandler: confirmationClient
        )

        _ = try await fulcrum.refreshTransactionHistory(for: account, usage: .receiving, includeUnconfirmed: true)

        do {
            _ = try await fulcrum.updateTransactionConfirmations(
                for: account,
                transactionHashes: [hash]
            )
            Issue.record("Expected mismatched confirmation count to fail")
        } catch let error as OpalBase.Account.Error {
            guard case .transactionConfirmationRefreshFailed(let failedHash, let underlying) = error else {
                Issue.record("Unexpected account error: \(error)")
                return
            }
            #expect(failedHash == hash)
            let networkError = try #require(underlying as? OpalBase.Network.Error)
            #expect(networkError.reason == .protocolViolation)
            #expect(networkError.message == "Confirmation status count does not match height and tip")
        }

        let record = try #require(await account.loadTransactionHistory().first { $0.transactionHash == hash })
        #expect(record.status == .discovered)
        #expect(record.confirmationMetadata.height == nil)
    }

    @Test("refreshTransactionConfirmations updates all tracked transactions")
    func refreshTransactionConfirmationsUsesKnownHistory() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let firstEntry = try await account.reserveNextReceivingEntry()
        let secondEntry = try await account.reserveNextReceivingEntry()
        let hashA = AccountTestFixtures.makeHash(byte: 0x41)
        let hashB = AccountTestFixtures.makeHash(byte: 0x42)

        let addressReader = WalletAddressReaderTestActor(
            historyByAddress: [
                firstEntry.address.string: [.init(transactionIdentifier: hashA.reverseOrder.hexadecimalString, blockHeight: 3, fee: nil)],
                secondEntry.address.string: [.init(transactionIdentifier: hashB.reverseOrder.hexadecimalString, blockHeight: 4, fee: nil)]
            ]
        )
        let confirmationClient = TransactionConfirmationClientTestActor(
            statusesByHash: [
                hashA: .init(transactionHash: hashA, transactionHeight: 8, tipHeight: 20, confirmations: 13),
                hashB: .init(transactionHash: hashB, transactionHeight: 9, tipHeight: 20, confirmations: 12)
            ]
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
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

private enum BalanceRefreshTestFailure: Error {
    case rejected
}
