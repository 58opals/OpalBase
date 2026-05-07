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

    @Test("address book snapshot rejects category-only token UTXOs")
    func addressBookSnapshotRejectsCategoryOnlyTokenUTXOs() throws {
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x01, count: 32))
        let unspentOutputSnapshot = OpalBase.Address.Book.Snapshot.UTXO(
            value: 500,
            lockingScript: "51",
            tokenCategory: category.hexForDisplay,
            tokenAmount: nil,
            nftCapability: nil,
            nftCommitment: nil,
            transactionHash: String(repeating: "0", count: 64),
            outputIndex: 1
        )

        #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotTokenData(
                reason: OpalBase.CashTokens.Error.invalidTokenPrefix
            )
        ) {
            _ = try unspentOutputSnapshot.makeTokenData()
        }
    }

    @Test("address book snapshot rejects zero fungible token amounts")
    func addressBookSnapshotRejectsZeroFungibleTokenAmounts() throws {
        let category = try OpalBase.CashTokens.CategoryID(transactionOrderData: Data(repeating: 0x02, count: 32))
        let unspentOutputSnapshot = OpalBase.Address.Book.Snapshot.UTXO(
            value: 500,
            lockingScript: "51",
            tokenCategory: category.hexForDisplay,
            tokenAmount: 0,
            nftCapability: nil,
            nftCommitment: nil,
            transactionHash: String(repeating: "0", count: 64),
            outputIndex: 1
        )

        #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotTokenData(
                reason: OpalBase.CashTokens.Error.invalidTokenPrefixFungibleAmount
            )
        ) {
            _ = try unspentOutputSnapshot.makeTokenData()
        }
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

    @Test("address book restore rejects entries in the wrong usage bucket")
    func addressBookRestoreRejectsWrongUsageBucket() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )
        let snapshot = await book.makeSnapshot()
        let firstReceivingEntry = try #require(snapshot.receivingEntries.first)
        let mismatchedReceivingEntry = OpalBase.Address.Book.Snapshot.Entry(
            usage: .change,
            index: firstReceivingEntry.index,
            isUsed: firstReceivingEntry.isUsed,
            isReserved: firstReceivingEntry.isReserved,
            balance: 9_999,
            lastUpdated: firstReceivingEntry.lastUpdated
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: [mismatchedReceivingEntry] + snapshot.receivingEntries.dropFirst(),
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: snapshot.transactions
        )

        await #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotEntryUsage(
                expected: .receiving,
                actual: .change,
                index: firstReceivingEntry.index
            )
        ) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects duplicate entry indices before mutation")
    func addressBookRestoreRejectsDuplicateEntryIndicesBeforeMutation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let firstReceivingEntry = try #require(snapshot.receivingEntries.first)
        let duplicateReceivingEntry = OpalBase.Address.Book.Snapshot.Entry(
            usage: firstReceivingEntry.usage,
            index: firstReceivingEntry.index,
            isUsed: true,
            isReserved: false,
            balance: 9_999,
            lastUpdated: firstReceivingEntry.lastUpdated
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: [firstReceivingEntry, duplicateReceivingEntry] + snapshot.receivingEntries.dropFirst(),
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: snapshot.transactions
        )

        await #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotDuplicateEntry(
                usage: .receiving,
                index: firstReceivingEntry.index
            )
        ) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects reserved entries that are not marked used before mutation")
    func addressBookRestoreRejectsReservedEntriesThatAreNotMarkedUsedBeforeMutation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let firstReceivingEntry = try #require(snapshot.receivingEntries.first)
        let malformedReceivingEntry = OpalBase.Address.Book.Snapshot.Entry(
            usage: firstReceivingEntry.usage,
            index: firstReceivingEntry.index,
            isUsed: false,
            isReserved: true,
            balance: 9_999,
            lastUpdated: firstReceivingEntry.lastUpdated
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: [malformedReceivingEntry] + snapshot.receivingEntries.dropFirst(),
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: snapshot.transactions
        )

        await #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotEntryReservationState(
                usage: .receiving,
                index: firstReceivingEntry.index
            )
        ) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
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

        await #expect(
            throws: Data.Error.cannotConvertHexadecimalStringToData
        ) {
            try await book.refresh(with: malformedSnapshot)
        }

        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects malformed UTXO hashes before mutation")
    func addressBookRestoreRejectsMalformedUTXOHashesBeforeMutation() async throws {
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
            lockingScript: entry.address.lockingScript.data.hexadecimalString,
            tokenCategory: nil,
            tokenAmount: nil,
            nftCapability: nil,
            nftCommitment: nil,
            transactionHash: "abcd",
            outputIndex: 0
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: [malformedUTXO],
            transactions: snapshot.transactions
        )

        await #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotTransactionHashLength(
                expected: OpalBase.Transaction.Hash.expectedByteCount,
                actual: 2
            )
        ) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects untracked UTXO locking scripts before mutation")
    func addressBookRestoreRejectsUntrackedUTXOLockingScriptsBeforeMutation() async throws {
        let account = try await AccountTestFixtures.makeAccount(unhardenedIndex: 0)
        let foreignAccount = try await AccountTestFixtures.makeAccount(unhardenedIndex: 1)
        let book = await account.addressBook
        let foreignBook = await foreignAccount.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        let foreignEntry = try #require(await foreignBook.listEntries(for: .receiving).first)
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
        let foreignUTXO = OpalBase.Address.Book.Snapshot.UTXO(
            value: 500,
            lockingScript: foreignEntry.address.lockingScript.data.hexadecimalString,
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
            utxos: [foreignUTXO],
            transactions: snapshot.transactions
        )

        await #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotUTXOLockingScript(
                foreignEntry.address.lockingScript.data
            )
        ) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
        #expect(await book.listSpendableUTXOs().isEmpty)
    }

    @Test("address book restore rejects UTXO values above maximum supply before mutation")
    func addressBookRestoreRejectsOversizedUTXOValuesBeforeMutation() async throws {
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
        let oversizedValue = OpalBase.Satoshi.maximumSatoshi + 1
        let malformedUTXO = OpalBase.Address.Book.Snapshot.UTXO(
            value: oversizedValue,
            lockingScript: entry.address.lockingScript.data.hexadecimalString,
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

        await #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotBalance(
                value: oversizedValue,
                reason: OpalBase.Satoshi.Error.exceedsMaximumAmount
            )
        ) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects duplicate UTXO outpoints before mutation")
    func addressBookRestoreRejectsDuplicateUTXOOutpointsBeforeMutation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        let transactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 1, count: 32))
        let originalUTXO = OpalBase.Transaction.Output.Unspent(
            value: 500,
            lockingScript: entry.address.lockingScript.data,
            previousTransactionHash: transactionHash,
            previousTransactionOutputIndex: 0
        )
        await book.addUTXO(originalUTXO)

        let snapshot = await book.makeSnapshot()
        let firstUTXO = try #require(snapshot.utxos.first)
        let duplicateUTXO = OpalBase.Address.Book.Snapshot.UTXO(
            value: 9_999,
            lockingScript: firstUTXO.lockingScript,
            tokenCategory: firstUTXO.tokenCategory,
            tokenAmount: firstUTXO.tokenAmount,
            nftCapability: firstUTXO.nftCapability,
            nftCommitment: firstUTXO.nftCommitment,
            transactionHash: firstUTXO.transactionHash,
            outputIndex: firstUTXO.outputIndex
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: snapshot.receivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: [firstUTXO, duplicateUTXO],
            transactions: snapshot.transactions
        )

        await #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotDuplicateUTXO(
                transactionHash: transactionHash,
                outputIndex: firstUTXO.outputIndex
            )
        ) {
            try await book.refresh(with: malformedSnapshot)
        }

        let storedUTXO = try #require(await book.listUTXOs(for: entry.address).first)
        #expect(storedUTXO.value == 500)
    }

    @Test("address book restore rejects malformed transaction hashes before mutation")
    func addressBookRestoreRejectsMalformedTransactionHashesBeforeMutation() async throws {
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
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: "abcd",
            height: 1,
            fee: nil,
            scriptHashes: [entry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .confirmed,
            confirmationHeight: 1,
            confirmedAt: .now,
            verificationStatus: .pending,
            merkleProof: nil,
            lastVerifiedHeight: nil,
            lastCheckedAt: nil
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotTransactionHashLength(
                expected: OpalBase.Transaction.Hash.expectedByteCount,
                actual: 2
            )
        ) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects duplicate transaction hashes before mutation")
    func addressBookRestoreRejectsDuplicateTransactionHashesBeforeMutation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let receivingEntry = try #require(await book.listEntries(for: .receiving).first)
        let changeEntry = try #require(await book.listEntries(for: .change).first)
        try await book.updateCachedBalance(
            for: receivingEntry.address,
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
                balance: snapshotEntry.index == receivingEntry.derivationPath.index ? 9_999 : snapshotEntry.balance,
                lastUpdated: snapshotEntry.lastUpdated
            )
        }
        let transactionHashData = Data(repeating: 2, count: OpalBase.Transaction.Hash.expectedByteCount)
        let transactionHash = OpalBase.Transaction.Hash(naturalOrder: transactionHashData)
        let firstTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: transactionHashData.hexadecimalString,
            height: 0,
            fee: nil,
            scriptHashes: [receivingEntry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .pending,
            confirmationHeight: nil,
            confirmedAt: nil,
            verificationStatus: .pending,
            merkleProof: nil,
            lastVerifiedHeight: nil,
            lastCheckedAt: nil
        )
        let secondTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: transactionHashData.hexadecimalString,
            height: 0,
            fee: nil,
            scriptHashes: [changeEntry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .pending,
            confirmationHeight: nil,
            confirmedAt: nil,
            verificationStatus: .pending,
            merkleProof: nil,
            lastVerifiedHeight: nil,
            lastCheckedAt: nil
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [firstTransaction, secondTransaction]
        )

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotDuplicateTransaction(transactionHash)) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: receivingEntry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects malformed transaction script hashes before mutation")
    func addressBookRestoreRejectsMalformedTransactionScriptHashesBeforeMutation() async throws {
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
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 0,
            fee: nil,
            scriptHashes: ["abcd"],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .pending,
            confirmationHeight: nil,
            confirmedAt: nil,
            verificationStatus: .pending,
            merkleProof: nil,
            lastVerifiedHeight: nil,
            lastCheckedAt: nil
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotScriptHashLength(
                expected: OpalBase.Transaction.Hash.expectedByteCount,
                actual: 2
            )
        ) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects transactions without script hashes before mutation")
    func addressBookRestoreRejectsTransactionsWithoutScriptHashesBeforeMutation() async throws {
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
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 0,
            fee: nil,
            scriptHashes: [],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .pending,
            confirmationHeight: nil,
            confirmedAt: nil,
            verificationStatus: .pending,
            merkleProof: nil,
            lastVerifiedHeight: nil,
            lastCheckedAt: nil
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotMissingScriptHashes) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects duplicate transaction script hashes before mutation")
    func addressBookRestoreRejectsDuplicateTransactionScriptHashesBeforeMutation() async throws {
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
        let scriptHash = entry.address.makeScriptHash().hexadecimalString
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 0,
            fee: nil,
            scriptHashes: [scriptHash, scriptHash],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .pending,
            confirmationHeight: nil,
            confirmedAt: nil,
            verificationStatus: .pending,
            merkleProof: nil,
            lastVerifiedHeight: nil,
            lastCheckedAt: nil
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotDuplicateScriptHash(scriptHash)) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects duplicate non-fungible token deltas before mutation")
    func addressBookRestoreRejectsDuplicateNonFungibleTokenDeltasBeforeMutation() async throws {
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
        let tokenData = try makeTokenDataWithNonFungibleToken()
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 0,
            fee: nil,
            scriptHashes: [entry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .pending,
            confirmationHeight: nil,
            confirmedAt: nil,
            verificationStatus: .pending,
            merkleProof: nil,
            lastVerifiedHeight: nil,
            lastCheckedAt: nil,
            nonFungibleTokenAdditions: [tokenData, tokenData]
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotDuplicateTokenDelta(tokenData)) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects malformed merkle proof branch hashes before mutation")
    func addressBookRestoreRejectsMalformedMerkleProofBranchHashesBeforeMutation() async throws {
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
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 1,
            fee: nil,
            scriptHashes: [entry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .confirmed,
            confirmationHeight: 1,
            confirmedAt: .now,
            verificationStatus: .verified,
            merkleProof: .init(
                blockHeight: 1,
                position: 0,
                branch: ["abcd"],
                blockHash: nil
            ),
            lastVerifiedHeight: 1,
            lastCheckedAt: .now
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotMerkleProofHashLength(
                expected: OpalBase.Transaction.Hash.expectedByteCount,
                actual: 2
            )
        ) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects malformed merkle proof block hashes before mutation")
    func addressBookRestoreRejectsMalformedMerkleProofBlockHashesBeforeMutation() async throws {
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
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 1,
            fee: nil,
            scriptHashes: [entry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .confirmed,
            confirmationHeight: 1,
            confirmedAt: .now,
            verificationStatus: .verified,
            merkleProof: .init(
                blockHeight: 1,
                position: 0,
                branch: [],
                blockHash: "abcd"
            ),
            lastVerifiedHeight: 1,
            lastCheckedAt: .now
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotMerkleProofHashLength(
                expected: OpalBase.Transaction.Hash.expectedByteCount,
                actual: 2
            )
        ) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects verified transaction snapshots without merkle proof")
    func addressBookRestoreRejectsVerifiedSnapshotsWithoutMerkleProof() async throws {
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
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 1,
            fee: nil,
            scriptHashes: [entry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .confirmed,
            confirmationHeight: 1,
            confirmedAt: .now,
            verificationStatus: .verified,
            merkleProof: nil,
            lastVerifiedHeight: 1,
            lastCheckedAt: .now
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotVerificationState) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects verified transaction snapshots whose proof height mismatches confirmation height")
    func addressBookRestoreRejectsVerifiedSnapshotsWithMismatchedProofHeight() async throws {
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
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 2,
            fee: nil,
            scriptHashes: [entry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .confirmed,
            confirmationHeight: 2,
            confirmedAt: .now,
            verificationStatus: .verified,
            merkleProof: .init(
                blockHeight: 1,
                position: 0,
                branch: [],
                blockHash: nil
            ),
            lastVerifiedHeight: 1,
            lastCheckedAt: .now
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotVerificationState) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects verified transaction snapshots without verification timestamps")
    func addressBookRestoreRejectsVerifiedSnapshotsWithoutVerificationTimestamps() async throws {
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
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 2,
            fee: nil,
            scriptHashes: [entry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .confirmed,
            confirmationHeight: 2,
            confirmedAt: .now,
            verificationStatus: .verified,
            merkleProof: .init(
                blockHeight: 2,
                position: 0,
                branch: [],
                blockHash: nil
            ),
            lastVerifiedHeight: nil,
            lastCheckedAt: nil
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotVerificationState) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects confirmed transaction snapshots without confirmation height")
    func addressBookRestoreRejectsConfirmedSnapshotsWithoutConfirmationHeight() async throws {
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
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 10,
            fee: nil,
            scriptHashes: [entry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .confirmed,
            confirmationHeight: nil,
            confirmedAt: .now,
            verificationStatus: .pending,
            merkleProof: nil,
            lastVerifiedHeight: nil,
            lastCheckedAt: nil
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotConfirmationState) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects confirmed transaction snapshots without confirmation timestamp")
    func addressBookRestoreRejectsConfirmedSnapshotsWithoutConfirmationTimestamp() async throws {
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
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 10,
            fee: nil,
            scriptHashes: [entry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .confirmed,
            confirmationHeight: 10,
            confirmedAt: nil,
            verificationStatus: .pending,
            merkleProof: nil,
            lastVerifiedHeight: nil,
            lastCheckedAt: nil
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotConfirmationState) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects confirmed snapshots with mismatched chain and confirmation heights")
    func addressBookRestoreRejectsConfirmedSnapshotsWithMismatchedHeights() async throws {
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
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 9,
            fee: nil,
            scriptHashes: [entry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .confirmed,
            confirmationHeight: 10,
            confirmedAt: .now,
            verificationStatus: .pending,
            merkleProof: nil,
            lastVerifiedHeight: nil,
            lastCheckedAt: nil
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotConfirmationState) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects unconfirmed snapshots with confirmation metadata")
    func addressBookRestoreRejectsUnconfirmedSnapshotsWithConfirmationMetadata() async throws {
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
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 0,
            fee: nil,
            scriptHashes: [entry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .pending,
            confirmationHeight: 1,
            confirmedAt: .now,
            verificationStatus: .pending,
            merkleProof: nil,
            lastVerifiedHeight: nil,
            lastCheckedAt: nil
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotConfirmationState) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects non-confirmed snapshots with confirmed chain heights")
    func addressBookRestoreRejectsNonConfirmedSnapshotsWithConfirmedChainHeights() async throws {
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
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 10,
            fee: nil,
            scriptHashes: [entry.address.makeScriptHash().hexadecimalString],
            firstSeenAt: .now,
            lastUpdatedAt: .now,
            status: .pending,
            confirmationHeight: nil,
            confirmedAt: nil,
            verificationStatus: .pending,
            merkleProof: nil,
            lastVerifiedHeight: nil,
            lastCheckedAt: nil
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotConfirmationState) {
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
