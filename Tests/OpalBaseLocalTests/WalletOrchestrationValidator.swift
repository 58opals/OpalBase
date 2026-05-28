// WalletOrchestrationValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Wallet orchestration", .tags(.unit, .wallet))
struct WalletOrchestrationValidator {
    @Test("prepareSpend(forAccountAt:) delegates to the selected account")
    func prepareSpendDelegatesToSelectedAccount() async throws {
        let wallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let account = try await wallet.fetchAccount(at: 0)
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 25_000,
            hashByte: 0x01
        )

        let recipient = OpalBase.Account.Payment.Recipient(
            address: try OpalBase.Address(AccountTestFixtures.standardAddressString),
            amount: try OpalBase.Satoshi(10_000)
        )
        let payment = OpalBase.Account.Payment(recipients: [recipient])

        let plan = try await wallet.prepareSpend(forAccountAt: 0, payment: payment)
        #expect(plan.inputs.count == 1)
        try await plan.cancelReservation()
    }

    @Test("prepareSpend(forAccountAt:) surfaces cannotFetchAccount for missing indices")
    func prepareSpendPropagatesMissingAccountErrors() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
        let payment = OpalBase.Account.Payment(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixtures.standardAddressString),
                    amount: try OpalBase.Satoshi(1_000)
                )
            ]
        )

        await #expect(throws: OpalBase.Wallet.Error.cannotFetchAccount(index: 9)) {
            _ = try await wallet.prepareSpend(forAccountAt: 9, payment: payment)
        }
    }

    @Test("calculateBalance aggregates across accounts and updates cached totals")
    func calculateBalanceAggregatesAcrossAccounts() async throws {
        let wallet = try await AccountTestFixtures.makeWallet(accountIndices: [0, 1])
        let account0 = try await wallet.fetchAccount(at: 0)
        let account1 = try await wallet.fetchAccount(at: 1)

        let account0Address = try await account0.selectNextEntry(for: .receiving).address
        let account1Address = try await account1.selectNextEntry(for: .receiving).address

        let balanceByAddress: [OpalBase.Address: OpalBase.Satoshi] = [
            account0Address: try OpalBase.Satoshi(1_200),
            account1Address: try OpalBase.Satoshi(3_400)
        ]

        let liveTotal = try await wallet.calculateBalance { address in
            balanceByAddress[address] ?? OpalBase.Satoshi()
        }
        let expectedTotal = try OpalBase.Satoshi(1_200) + OpalBase.Satoshi(3_400)
        #expect(liveTotal == expectedTotal)

        let cachedTotal = try await wallet.calculateCachedBalance()
        #expect(cachedTotal == expectedTotal)
    }

    @Test("applySnapshot refreshes overlapping account actors in place")
    func applySnapshotRefreshesExistingAccountState() async throws {
        let sourceWallet = try await AccountTestFixtures.makeWallet(accountIndices: [0, 3])
        let sourceAccount = try await sourceWallet.fetchAccount(at: 0)
        _ = try await sourceAccount.reserveNextReceivingAddress()
        let snapshot = await sourceWallet.makeSnapshot()

        let targetWallet = try OpalBase.Wallet(mnemonic: AccountTestFixtures.makeMnemonic())
        try await targetWallet.addAccount(unhardenedIndex: 0)
        try await targetWallet.addAccount(unhardenedIndex: 7)
        let existingAccount = try await targetWallet.fetchAccount(at: 0)

        try await targetWallet.applySnapshot(snapshot)

        _ = try await targetWallet.fetchAccount(at: 0)
        _ = try await targetWallet.fetchAccount(at: 3)

        let restoredAccount = try await targetWallet.fetchAccount(at: 0)
        let nextReceiving = try await restoredAccount.selectNextEntry(for: .receiving)
        #expect(existingAccount === restoredAccount)
        #expect(nextReceiving.derivationPath.index == 1)

        await #expect(throws: OpalBase.Wallet.Error.cannotFetchAccount(index: 7)) {
            _ = try await targetWallet.fetchAccount(at: 7)
        }
    }

    @Test("applySnapshot replaces omitted address-book entries on reused accounts")
    func applySnapshotReplacesOmittedAddressBookEntries() async throws {
        let sourceWallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let sourceAccount = try await sourceWallet.fetchAccount(at: 0)
        _ = try await sourceAccount.reserveNextReceivingAddress()
        let sourceSnapshot = await sourceWallet.makeSnapshot()
        let sourceAccountSnapshot = try #require(sourceSnapshot.accounts.first)

        let reducedAddressBookSnapshot = OpalBase.Account.Snapshot.AddressBook(
            receivingEntries: Array(sourceAccountSnapshot.addressBook.receivingEntries.prefix(2)),
            changeEntries: Array(sourceAccountSnapshot.addressBook.changeEntries.prefix(1)),
            utxos: sourceAccountSnapshot.addressBook.utxos,
            transactions: sourceAccountSnapshot.addressBook.transactions
        )
        let reducedWalletSnapshot = OpalBase.Wallet.Snapshot(
            purpose: sourceSnapshot.purpose,
            coinType: sourceSnapshot.coinType,
            accounts: [
                .init(
                    purpose: sourceAccountSnapshot.purpose,
                    coinType: sourceAccountSnapshot.coinType,
                    accountUnhardenedIndex: sourceAccountSnapshot.accountUnhardenedIndex,
                    addressBook: reducedAddressBookSnapshot
                )
            ],
            tokenMetadata: sourceSnapshot.tokenMetadata
        )

        let targetWallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let existingAccount = try await targetWallet.fetchAccount(at: 0)
        _ = try await existingAccount.reserveNextReceivingEntry()
        _ = try await existingAccount.reserveNextReceivingEntry()
        _ = try await existingAccount.reserveNextReceivingEntry()

        let inflatedReceivingCount = await existingAccount.addressBook.countEntries(for: .receiving)
        #expect(inflatedReceivingCount == 23)

        try await targetWallet.applySnapshot(reducedWalletSnapshot)

        let restoredAccount = try await targetWallet.fetchAccount(at: 0)
        let restoredReceivingEntries = await restoredAccount.addressBook.listEntries(for: .receiving)
        let restoredChangeEntries = await restoredAccount.addressBook.listEntries(for: .change)

        #expect(existingAccount === restoredAccount)
        #expect(restoredReceivingEntries.count == 21)
        let firstRestoredReceivingEntry = try #require(restoredReceivingEntries.first)
        let lastRestoredReceivingEntry = try #require(restoredReceivingEntries.last)
        #expect(lastRestoredReceivingEntry.derivationPath.index == 20)
        #expect(firstRestoredReceivingEntry.isUsed == true)
        #expect(firstRestoredReceivingEntry.isReserved == false)
        #expect(restoredReceivingEntries.dropFirst().allSatisfy { !$0.isReserved })
        #expect(restoredReceivingEntries.filter { !$0.isUsed && !$0.isReserved }.count == 20)
        #expect(restoredChangeEntries.count == 20)
        #expect(restoredChangeEntries.allSatisfy { !$0.isUsed && !$0.isReserved })
    }

    @Test("applySnapshot rejects snapshots with a mismatched derivation path")
    func applySnapshotRejectsDerivationMismatch() async throws {
        let wallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let snapshot = await wallet.makeSnapshot()

        let mismatchedSnapshot = OpalBase.Wallet.Snapshot(
            purpose: snapshot.purpose,
            coinType: .bitcoin,
            accounts: snapshot.accounts,
            tokenMetadata: snapshot.tokenMetadata
        )

        await #expect(throws: OpalBase.Wallet.Error.snapshotDoesNotMatchWallet) {
            try await wallet.applySnapshot(mismatchedSnapshot)
        }
    }

    @Test("applySnapshot rejects duplicate account indices without mutating existing state")
    func applySnapshotRejectsDuplicateAccountIndices() async throws {
        let sourceWallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let sourceSnapshot = await sourceWallet.makeSnapshot()
        let duplicatedAccountSnapshot = try #require(sourceSnapshot.accounts.first)
        let duplicateSnapshot = OpalBase.Wallet.Snapshot(
            purpose: sourceSnapshot.purpose,
            coinType: sourceSnapshot.coinType,
            accounts: [duplicatedAccountSnapshot, duplicatedAccountSnapshot],
            tokenMetadata: sourceSnapshot.tokenMetadata
        )

        let targetWallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let existingAccount = try await targetWallet.fetchAccount(at: 0)
        _ = try await existingAccount.reserveNextReceivingEntry()

        #expect(await existingAccount.addressBook.countEntries(for: .receiving) == 21)

        await #expect(throws: OpalBase.Wallet.Error.snapshotDoesNotMatchWallet) {
            try await targetWallet.applySnapshot(duplicateSnapshot)
        }

        let restoredAccount = try await targetWallet.fetchAccount(at: 0)
        #expect(existingAccount === restoredAccount)
        #expect(await restoredAccount.addressBook.countEntries(for: .receiving) == 21)
    }

    @Test("applySnapshot leaves existing account state unchanged when a later snapshot account is malformed")
    func applySnapshotPreservesExistingStateWhenLaterAccountIsMalformed() async throws {
        let sourceWallet = try await AccountTestFixtures.makeWallet(accountIndices: [0, 3])
        let sourceAccount = try await sourceWallet.fetchAccount(at: 0)
        _ = try await sourceAccount.reserveNextReceivingEntry()
        let sourceSnapshot = await sourceWallet.makeSnapshot()
        let validSnapshot = try #require(sourceSnapshot.accounts.first { $0.accountUnhardenedIndex == 0 })
        let invalidBaseSnapshot = try #require(sourceSnapshot.accounts.first { $0.accountUnhardenedIndex == 3 })

        let malformedAddressBook = OpalBase.Account.Snapshot.AddressBook(
            receivingEntries: invalidBaseSnapshot.addressBook.receivingEntries,
            changeEntries: invalidBaseSnapshot.addressBook.changeEntries,
            utxos: [
                .init(
                    value: 1,
                    lockingScript: "zz",
                    tokenCategory: nil,
                    tokenAmount: nil,
                    nftCapability: nil,
                    nftCommitment: nil,
                    transactionHash: "abcd",
                    outputIndex: 0
                )
            ],
            transactions: invalidBaseSnapshot.addressBook.transactions
        )
        let malformedAccountSnapshot = OpalBase.Account.Snapshot(
            purpose: invalidBaseSnapshot.purpose,
            coinType: invalidBaseSnapshot.coinType,
            accountUnhardenedIndex: invalidBaseSnapshot.accountUnhardenedIndex,
            addressBook: malformedAddressBook
        )
        let malformedSnapshot = OpalBase.Wallet.Snapshot(
            purpose: sourceSnapshot.purpose,
            coinType: sourceSnapshot.coinType,
            accounts: [validSnapshot, malformedAccountSnapshot],
            tokenMetadata: sourceSnapshot.tokenMetadata
        )

        let targetWallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let existingAccount = try await targetWallet.fetchAccount(at: 0)
        _ = try await existingAccount.reserveNextReceivingEntry()
        _ = try await existingAccount.reserveNextReceivingEntry()
        _ = try await existingAccount.reserveNextReceivingEntry()

        #expect(await existingAccount.addressBook.countEntries(for: .receiving) == 23)

        await #expect(throws: OpalBase.Wallet.Error.snapshotDoesNotMatchWallet) {
            try await targetWallet.applySnapshot(malformedSnapshot)
        }

        let restoredAccount = try await targetWallet.fetchAccount(at: 0)
        #expect(existingAccount === restoredAccount)
        #expect(await restoredAccount.addressBook.countEntries(for: .receiving) == 23)

        await #expect(throws: OpalBase.Wallet.Error.cannotFetchAccount(index: 3)) {
            _ = try await targetWallet.fetchAccount(at: 3)
        }
    }

    @Test("applySnapshot clears existing token metadata when snapshot omits it")
    func applySnapshotClearsExistingTokenMetadataForLegacySnapshots() async throws {
        let sourceWallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let targetWallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let staleCategory = try makeCategoryIdentifier(
            hexadecimalString: "1111111111111111111111111111111111111111111111111111111111111111"
        )
        let staleMetadata = makeMetadata(
            category: staleCategory,
            name: "Stale Token",
            symbol: "STALE",
            lastUpdated: Date(timeIntervalSince1970: 1)
        )

        await targetWallet.upsertTokenMetadata([staleCategory: staleMetadata])

        let snapshot = await sourceWallet.makeSnapshot()
        let legacySnapshot = OpalBase.Wallet.Snapshot(
            purpose: snapshot.purpose,
            coinType: snapshot.coinType,
            accounts: snapshot.accounts,
            tokenMetadata: nil
        )

        try await targetWallet.applySnapshot(legacySnapshot)

        #expect(await targetWallet.fetchTokenMetadata(for: staleCategory) == nil)
        #expect((await targetWallet.makeTokenMetadataSnapshot()).byCategory.isEmpty)
    }

    @Test("applySnapshot replaces existing token metadata with snapshot contents")
    func applySnapshotReplacesExistingTokenMetadata() async throws {
        let sourceWallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let targetWallet = try await AccountTestFixtures.makeWallet(accountIndices: [0])
        let snapshotCategory = try makeCategoryIdentifier(
            hexadecimalString: "2222222222222222222222222222222222222222222222222222222222222222"
        )
        let staleCategory = try makeCategoryIdentifier(
            hexadecimalString: "3333333333333333333333333333333333333333333333333333333333333333"
        )
        let staleMetadata = makeMetadata(
            category: staleCategory,
            name: "Stale Token",
            symbol: "STALE",
            lastUpdated: Date(timeIntervalSince1970: 2)
        )
        let preexistingSnapshotCategoryMetadata = makeMetadata(
            category: snapshotCategory,
            name: "Old Snapshot Token",
            symbol: "OLD",
            lastUpdated: Date(timeIntervalSince1970: 3)
        )
        let snapshotMetadata = makeMetadata(
            category: snapshotCategory,
            name: "Snapshot Token",
            symbol: "NEW",
            lastUpdated: Date(timeIntervalSince1970: 4)
        )

        await targetWallet.upsertTokenMetadata([
            staleCategory: staleMetadata,
            snapshotCategory: preexistingSnapshotCategoryMetadata
        ])
        await sourceWallet.upsertTokenMetadata([snapshotCategory: snapshotMetadata])

        let snapshot = await sourceWallet.makeSnapshot()
        try await targetWallet.applySnapshot(snapshot)

        #expect(await targetWallet.fetchTokenMetadata(for: staleCategory) == nil)
        let restoredMetadata = try #require(
            await targetWallet.fetchTokenMetadata(for: snapshotCategory)
        )
        #expect(restoredMetadata.name == "Snapshot Token")
        #expect(restoredMetadata.symbol == "NEW")

        let metadataSnapshot = await targetWallet.makeTokenMetadataSnapshot()
        #expect(Set(metadataSnapshot.byCategory.keys) == Set([snapshotCategory.hexForDisplay]))
    }

    @Test("wallet snapshots exclude mnemonic words and passphrase")
    func walletSnapshotExcludesSecrets() async throws {
        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "super-secret")
        let snapshot = await wallet.makeSnapshot()
        let encodedSnapshot = try JSONEncoder().encode(snapshot)
        let encodedSnapshotString = try #require(String(data: encodedSnapshot, encoding: .utf8))

        #expect(encodedSnapshotString.contains("super-secret") == false)
        for word in AccountTestFixtures.mnemonicWords {
            #expect(encodedSnapshotString.contains(word) == false)
        }
    }

    @Test("wallet restores from mnemonic plus snapshot")
    func walletRestoresFromMnemonicAndSnapshot() async throws {
        let sourceWallet = try await AccountTestFixtures.makeWallet(accountIndices: [0], passphrase: "restore-me")
        let sourceAccount = try await sourceWallet.fetchAccount(at: 0)
        _ = try await sourceAccount.reserveNextReceivingAddress()
        let snapshot = await sourceWallet.makeSnapshot()

        let restoredWallet = try await OpalBase.Wallet(
            mnemonic: try OpalBase.Key.Mnemonic(words: AccountTestFixtures.mnemonicWords.map(OpalBase.Key.Mnemonic.Word.init)),
            passphrase: "restore-me",
            from: snapshot
        )
        let restoredAccount = try await restoredWallet.fetchAccount(at: 0)
        let nextReceiving = try await restoredAccount.selectNextEntry(for: .receiving)

        #expect(nextReceiving.derivationPath.index == 1)
    }
}

private func makeCategoryIdentifier(hexadecimalString: String) throws -> OpalBase.CashTokens.CategoryID {
    try OpalBase.CashTokens.CategoryID(hexFromRPC: hexadecimalString)
}

private func makeMetadata(
    category: OpalBase.CashTokens.CategoryID,
    name: String,
    symbol: String,
    lastUpdated: Date
) -> OpalBase.CashTokens.Metadata {
    OpalBase.CashTokens.Metadata(
        category: category,
        name: name,
        symbol: symbol,
        decimals: 0,
        iconURL: nil,
        lastUpdated: lastUpdated,
        source: .embedded
    )
}
