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

    @Test(
        "address book snapshot rejects invalid token UTXO fields",
        arguments: InvalidSnapshotTokenUTXOFieldsCase.allCases
    )
    fileprivate func addressBookSnapshotRejectsInvalidTokenUTXOFields(
        _ invalidCase: InvalidSnapshotTokenUTXOFieldsCase
    ) throws {
        let unspentOutputSnapshot = try makeTokenUnspentOutputSnapshot(
            categoryByte: invalidCase.categoryByte,
            tokenAmount: invalidCase.tokenAmount,
            nftCapability: nil,
            nftCommitment: nil
        )

        #expect(
            throws: invalidCase.expectedError
        ) {
            _ = try unspentOutputSnapshot.makeTokenData()
        }
    }

    @Test(
        "address book snapshot rejects invalid NFT commitments",
        arguments: InvalidSnapshotNFTCommitmentCase.allCases
    )
    fileprivate func addressBookSnapshotRejectsInvalidNFTCommitments(
        _ invalidCase: InvalidSnapshotNFTCommitmentCase
    ) throws {
        let unspentOutputSnapshot = try makeTokenUnspentOutputSnapshot(
            categoryByte: 0x03,
            tokenAmount: nil,
            nftCapability: OpalBase.CashTokens.NFT.Capability.none,
            nftCommitment: invalidCase.commitment
        )

        #expect(
            throws: OpalBase.Address.Book.Error.invalidSnapshotTokenData(
                reason: OpalBase.CashTokens.Error.invalidHexadecimalString
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

        try #require(restoredReceivingEntries.count == 20)
        try #require(restoredChangeEntries.count == 20)
        let firstRestoredReceivingEntry = try #require(restoredReceivingEntries.first)
        let lastRestoredReceivingEntry = try #require(restoredReceivingEntries.last)
        let firstRestoredChangeEntry = try #require(restoredChangeEntries.first)
        let lastRestoredChangeEntry = try #require(restoredChangeEntries.last)
        #expect(await book.countUnusedEntries(for: .receiving) == 20)
        #expect(await book.countUnusedEntries(for: .change) == 20)
        #expect(firstRestoredReceivingEntry.derivationPath.index == 0)
        #expect(lastRestoredReceivingEntry.derivationPath.index == 19)
        #expect(firstRestoredChangeEntry.derivationPath.index == 0)
        #expect(lastRestoredChangeEntry.derivationPath.index == 19)
        #expect(restoredReceivingEntries.allSatisfy { !$0.isUsed && !$0.isReserved })
        #expect(restoredChangeEntries.allSatisfy { !$0.isUsed && !$0.isReserved })
    }

    @Test("address book restore preserves trailing gap after sparse used entries")
    func addressBookRestorePreservesTrailingGapAfterSparseUsedEntries() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let restoredSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: [
                .init(
                    usage: .receiving,
                    index: 25,
                    isUsed: true,
                    isReserved: false,
                    balance: nil,
                    lastUpdated: nil
                )
            ],
            changeEntries: [],
            utxos: [],
            transactions: []
        )

        try await book.refresh(with: restoredSnapshot)

        let restoredReceivingEntries = await book.listEntries(for: .receiving)
        let restoredReceivingIndexes = restoredReceivingEntries.map(\.derivationPath.index)

        #expect(restoredReceivingEntries.count == 46)
        #expect(restoredReceivingIndexes.suffix(20) == Array(UInt32(26)...UInt32(45)))
        #expect(restoredReceivingEntries.suffix(20).allSatisfy { !$0.isUsed && !$0.isReserved })
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

    @Test("address book restore rejects hardened entry indexes")
    func addressBookRestoreRejectsHardenedEntryIndexes() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let originalReceivingEntryCount = await book.countEntries(for: .receiving)
        let originalChangeEntryCount = await book.countEntries(for: .change)
        let snapshot = await book.makeSnapshot()
        let firstReceivingEntry = try #require(snapshot.receivingEntries.first)
        let hardenedReceivingEntry = OpalBase.Address.Book.Snapshot.Entry(
            usage: firstReceivingEntry.usage,
            index: HardenedIndex.bit,
            isUsed: firstReceivingEntry.isUsed,
            isReserved: firstReceivingEntry.isReserved,
            balance: firstReceivingEntry.balance,
            lastUpdated: firstReceivingEntry.lastUpdated
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: [hardenedReceivingEntry] + snapshot.receivingEntries.dropFirst(),
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: snapshot.transactions
        )

        await #expect(throws: OpalBase.Address.Book.Error.indexOutOfBounds) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(await book.countEntries(for: .receiving) == originalReceivingEntryCount)
        #expect(await book.countEntries(for: .change) == originalChangeEntryCount)
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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
            throws: OpalBase.Address.Book.Error.invalidSnapshotUTXOLockingScriptHex("not-hex")
        ) {
            try await book.refresh(with: malformedSnapshot)
        }

        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test(
        "address book restore rejects invalid UTXO transaction hashes before mutation",
        arguments: InvalidSnapshotUTXOTransactionHashCase.allCases
    )
    fileprivate func addressBookRestoreRejectsInvalidUTXOTransactionHashesBeforeMutation(
        _ invalidCase: InvalidSnapshotUTXOTransactionHashCase
    ) async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
        let malformedUTXO = OpalBase.Address.Book.Snapshot.UTXO(
            value: 500,
            lockingScript: entry.address.lockingScript.data.hexadecimalString,
            tokenCategory: nil,
            tokenAmount: nil,
            nftCapability: nil,
            nftCommitment: nil,
            transactionHash: invalidCase.transactionHash,
            outputIndex: 0
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: [malformedUTXO],
            transactions: snapshot.transactions
        )

        await #expect(
            throws: invalidCase.expectedError
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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

    @Test("address book restore rejects prefixed UTXO locking scripts before mutation")
    func rejectPrefixedUnspentOutputLockingScriptsBeforeAddressBookRestoreMutation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
        let prefixedLockingScript = "0x\(entry.address.lockingScript.data.hexadecimalString)"
        let malformedUTXO = OpalBase.Address.Book.Snapshot.UTXO(
            value: 500,
            lockingScript: prefixedLockingScript,
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
            throws: OpalBase.Address.Book.Error.invalidSnapshotUTXOLockingScriptHex(prefixedLockingScript)
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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

    @Test("address book restore rejects invalid transaction hashes before mutation", arguments: InvalidSnapshotTransactionHashCase.allCases)
    fileprivate func addressBookRestoreRejectsInvalidTransactionHashesBeforeMutation(_ invalidCase: InvalidSnapshotTransactionHashCase) async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: invalidCase.transactionHash,
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
            throws: invalidCase.expectedError
        ) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects transaction fees above maximum supply before mutation")
    func addressBookRestoreRejectsOversizedTransactionFeesBeforeMutation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
        let oversizedFee = OpalBase.Satoshi.maximumSatoshi + 1
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 1,
            fee: oversizedFee,
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
            throws: OpalBase.Address.Book.Error.invalidSnapshotFee(
                value: oversizedFee,
                reason: OpalBase.Satoshi.Error.exceedsMaximumAmount
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: receivingEntry)
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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

    @Test("address book restore rejects prefixed transaction script hashes before mutation")
    func rejectPrefixedTransactionScriptHashesBeforeAddressBookRestoreMutation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
        let prefixedScriptHash = "0x\(entry.address.makeScriptHash().hexadecimalString)"
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 0,
            fee: nil,
            scriptHashes: [prefixedScriptHash],
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

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotScriptHash(prefixedScriptHash)) {
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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

    @Test("address book restore canonicalizes uppercase transaction script hashes")
    func addressBookRestoreCanonicalizesUppercaseTransactionScriptHashes() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(
            await book.listEntries(for: .receiving).first { entry in
                let scriptHash = entry.address.makeScriptHash().hexadecimalString
                return scriptHash != scriptHash.uppercased()
            }
        )
        let scriptHash = entry.address.makeScriptHash().hexadecimalString
        let uppercaseScriptHash = scriptHash.uppercased()
        let snapshot = await book.makeSnapshot()
        let transaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 0,
            fee: nil,
            scriptHashes: [uppercaseScriptHash],
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
        let restoredSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: snapshot.receivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [transaction]
        )

        try await book.refresh(with: restoredSnapshot)

        let record = try #require(await book.listTransactionRecords().first)
        #expect(record.chainMetadata.scriptHashes == [scriptHash])
    }

    @Test("address book restore rejects duplicate transaction script hashes with different casing")
    func addressBookRestoreRejectsDuplicateTransactionScriptHashesWithDifferentCasing() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(
            await book.listEntries(for: .receiving).first { entry in
                let scriptHash = entry.address.makeScriptHash().hexadecimalString
                return scriptHash != scriptHash.uppercased()
            }
        )
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
        let scriptHash = entry.address.makeScriptHash().hexadecimalString
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 0,
            fee: nil,
            scriptHashes: [scriptHash, scriptHash.uppercased()],
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
        #expect(await book.listTransactionRecords().isEmpty)
    }

    @Test("address book restore rejects untracked transaction script hashes before mutation")
    func addressBookRestoreRejectsUntrackedTransactionScriptHashesBeforeMutation() async throws {
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
        let foreignScriptHash = foreignEntry.address.makeScriptHash().hexadecimalString
        let malformedTransaction = OpalBase.Address.Book.Snapshot.Transaction(
            transactionHash: String(repeating: "1", count: 64),
            height: 0,
            fee: nil,
            scriptHashes: [foreignScriptHash],
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

        await #expect(throws: OpalBase.Address.Book.Error.invalidSnapshotTransactionScriptHash(foreignScriptHash)) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
        #expect(await book.listTransactionRecords().isEmpty)
    }

    @Test("address book restore preserves duplicate non-fungible token deltas")
    func preserveDuplicateNonFungibleTokenDeltasDuringAddressBookRestore() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
        let tokenData = try makeTokenDataWithNonFungibleToken()
        let nonFungibleToken = try #require(tokenData.nft)
        let canonicalTokenData = OpalBase.CashTokens.TokenData(
            category: tokenData.category,
            amount: nil,
            nft: nonFungibleToken
        )
        let duplicateTokenData = OpalBase.CashTokens.TokenData(
            category: tokenData.category,
            amount: 42,
            nft: nonFungibleToken
        )
        let restoredTransaction = OpalBase.Address.Book.Snapshot.Transaction(
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
            nonFungibleTokenAdditions: [tokenData, duplicateTokenData]
        )
        let restoredSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [restoredTransaction]
        )

        try await book.refresh(with: restoredSnapshot)

        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(9_999))
        let restoredRecord = try #require(await book.listTransactionRecords().first)
        #expect(restoredRecord.tokenDelta.nonFungibleTokenAdditions == [
            canonicalTokenData,
            canonicalTokenData
        ])
    }

    @Test("address book restore rejects impossible BCH token lock deltas before mutation")
    func addressBookRestoreRejectsImpossibleBCHTokenLockDeltasBeforeMutation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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
            bchLockedInTokenOutputDelta: Int64(OpalBase.Satoshi.maximumSatoshi) + 1
        )
        let malformedSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [malformedTransaction]
        )

        await #expect(throws: OpalBase.Address.Book.Error.tokenDeltaOverflow) {
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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

    @Test("address book restore rejects prefixed merkle proof branch hashes before mutation")
    func rejectPrefixedMerkleProofBranchHashesBeforeAddressBookRestoreMutation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
        let prefixedBranchHash = "0x\(String(repeating: "1", count: 64))"
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
                branch: [prefixedBranchHash],
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
            throws: OpalBase.Address.Book.Error.invalidSnapshotMerkleProofHash(prefixedBranchHash)
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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

    @Test("address book restore rejects prefixed merkle proof block hashes before mutation")
    func rejectPrefixedMerkleProofBlockHashesBeforeAddressBookRestoreMutation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
        let prefixedBlockHash = "0x\(String(repeating: "1", count: 64))"
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
                blockHash: prefixedBlockHash
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
            throws: OpalBase.Address.Book.Error.invalidSnapshotMerkleProofHash(prefixedBlockHash)
        ) {
            try await book.refresh(with: malformedSnapshot)
        }
        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(1_234))
    }

    @Test("address book restore rejects out-of-range merkle proof positions before mutation")
    func addressBookRestoreRejectsOutOfRangeMerkleProofPositionsBeforeMutation() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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
                position: 2,
                branch: [String(repeating: "2", count: 64)],
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

    @Test("address book restore accepts highest merkle proof position for branch length")
    func addressBookRestoreAcceptsHighestMerkleProofPositionForBranchLength() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let book = await account.addressBook
        let entry = try #require(await book.listEntries(for: .receiving).first)
        try await book.updateCachedBalance(
            for: entry.address,
            balance: try OpalBase.Satoshi(1_234),
            timestamp: .now
        )

        let snapshot = await book.makeSnapshot()
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
        let transaction = OpalBase.Address.Book.Snapshot.Transaction(
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
                position: 1,
                branch: [String(repeating: "2", count: 64)],
                blockHash: nil
            ),
            lastVerifiedHeight: 1,
            lastCheckedAt: .now
        )
        let restoredSnapshot = OpalBase.Address.Book.Snapshot(
            receivingEntries: alteredReceivingEntries,
            changeEntries: snapshot.changeEntries,
            utxos: snapshot.utxos,
            transactions: [transaction]
        )

        try await book.refresh(with: restoredSnapshot)

        #expect(try await book.readCachedBalance(for: entry.address) == OpalBase.Satoshi(9_999))
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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
        let alteredReceivingEntries = makeReceivingEntriesWithChangedBalance(from: snapshot, for: entry)
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

    private func makeTokenUnspentOutputSnapshot(
        categoryByte: UInt8,
        tokenAmount: UInt64?,
        nftCapability: OpalBase.CashTokens.NFT.Capability?,
        nftCommitment: String?
    ) throws -> OpalBase.Address.Book.Snapshot.UTXO {
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: categoryByte, count: 32)
        )
        return OpalBase.Address.Book.Snapshot.UTXO(
            value: 500,
            lockingScript: "51",
            tokenCategory: category.hexForDisplay,
            tokenAmount: tokenAmount,
            nftCapability: nftCapability,
            nftCommitment: nftCommitment,
            transactionHash: String(repeating: "0", count: 64),
            outputIndex: 1
        )
    }

    private func makeReceivingEntriesWithChangedBalance(
        from snapshot: OpalBase.Address.Book.Snapshot,
        for entry: OpalBase.Address.Book.Entry,
        balance: UInt64 = 9_999
    ) -> [OpalBase.Address.Book.Snapshot.Entry] {
        snapshot.receivingEntries.map { snapshotEntry in
            OpalBase.Address.Book.Snapshot.Entry(
                usage: snapshotEntry.usage,
                index: snapshotEntry.index,
                isUsed: snapshotEntry.isUsed,
                isReserved: snapshotEntry.isReserved,
                balance: snapshotEntry.index == entry.derivationPath.index ? balance : snapshotEntry.balance,
                lastUpdated: snapshotEntry.lastUpdated
            )
        }
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

    enum InvalidSnapshotTransactionHashCase: CaseIterable, CustomStringConvertible, Sendable {
        case shortHex
        case malformedHex
        case prefixedHex
        case oversizedHex

        var description: String {
            switch self {
            case .shortHex:
                "short hex"
            case .malformedHex:
                "malformed hex"
            case .prefixedHex:
                "prefixed hex"
            case .oversizedHex:
                "oversized hex"
            }
        }

        var transactionHash: String {
            switch self {
            case .shortHex:
                "abcd"
            case .malformedHex:
                String(repeating: "0", count: 62) + "zz"
            case .prefixedHex:
                "0x\(String(repeating: "1", count: 64))"
            case .oversizedHex:
                String(repeating: "a", count: 4_096)
            }
        }

        var expectedError: OpalBase.Address.Book.Error {
            switch self {
            case .shortHex:
                OpalBase.Address.Book.Error.invalidSnapshotTransactionHashLength(
                    expected: OpalBase.Transaction.Hash.expectedByteCount,
                    actual: 2
                )
            case .malformedHex:
                OpalBase.Address.Book.Error.invalidSnapshotTransactionHash(transactionHash)
            case .prefixedHex:
                OpalBase.Address.Book.Error.invalidSnapshotTransactionHash(transactionHash)
            case .oversizedHex:
                OpalBase.Address.Book.Error.invalidSnapshotTransactionHashLength(
                    expected: OpalBase.Transaction.Hash.expectedByteCount,
                    actual: 2_048
                )
            }
        }
    }

    enum InvalidSnapshotUTXOTransactionHashCase: CaseIterable, CustomStringConvertible, Sendable {
        case shortHex
        case malformedHex
        case prefixedHex

        var description: String {
            switch self {
            case .shortHex:
                "short hex"
            case .malformedHex:
                "malformed hex"
            case .prefixedHex:
                "prefixed hex"
            }
        }

        var transactionHash: String {
            switch self {
            case .shortHex:
                "abcd"
            case .malformedHex:
                String(repeating: "0", count: 62) + "zz"
            case .prefixedHex:
                "0x\(String(repeating: "0", count: 64))"
            }
        }

        var expectedError: OpalBase.Address.Book.Error {
            switch self {
            case .shortHex:
                OpalBase.Address.Book.Error.invalidSnapshotTransactionHashLength(
                    expected: OpalBase.Transaction.Hash.expectedByteCount,
                    actual: 2
                )
            case .malformedHex:
                OpalBase.Address.Book.Error.invalidSnapshotTransactionHash(transactionHash)
            case .prefixedHex:
                OpalBase.Address.Book.Error.invalidSnapshotTransactionHash(transactionHash)
            }
        }
    }

    enum InvalidSnapshotNFTCommitmentCase: CaseIterable, CustomStringConvertible, Sendable {
        case prefixedHex
        case malformedHex

        var description: String {
            switch self {
            case .prefixedHex:
                "prefixed hex"
            case .malformedHex:
                "malformed hex"
            }
        }

        var commitment: String {
            switch self {
            case .prefixedHex:
                "0x12"
            case .malformedHex:
                "not-hex"
            }
        }
    }

    enum InvalidSnapshotTokenUTXOFieldsCase: CaseIterable, CustomStringConvertible, Sendable {
        case categoryOnly
        case zeroFungibleAmount
        case oversizedFungibleAmount

        var description: String {
            switch self {
            case .categoryOnly:
                "category only"
            case .zeroFungibleAmount:
                "zero fungible amount"
            case .oversizedFungibleAmount:
                "oversized fungible amount"
            }
        }

        var categoryByte: UInt8 {
            switch self {
            case .categoryOnly:
                0x01
            case .zeroFungibleAmount, .oversizedFungibleAmount:
                0x02
            }
        }

        var tokenAmount: UInt64? {
            switch self {
            case .categoryOnly:
                nil
            case .zeroFungibleAmount:
                0
            case .oversizedFungibleAmount:
                OpalBase.CashTokens.TokenData.maximumFungibleAmount + 1
            }
        }

        var expectedError: OpalBase.Address.Book.Error {
            switch self {
            case .categoryOnly:
                OpalBase.Address.Book.Error.invalidSnapshotTokenData(
                    reason: OpalBase.CashTokens.Error.invalidTokenPrefix
                )
            case .zeroFungibleAmount, .oversizedFungibleAmount:
                OpalBase.Address.Book.Error.invalidSnapshotTokenData(
                    reason: OpalBase.CashTokens.Error.invalidTokenPrefixFungibleAmount
                )
            }
        }
    }
}
