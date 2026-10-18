// StoragePersistenceValidator~SnapshotPersistence.swift

import Foundation
import Testing
@testable import OpalBase
@testable import OpalBaseCore

extension StoragePersistenceValidator {
    @Test(
        "snapshot-only persistence preserves fractional public timestamps",
        arguments: [0.125, 0.1234567]
    )
    func snapshotOnlyPersistencePreservesFractionalTimestamps(_ fractionalSeconds: Double) async throws {
        let storage = try OpalBase.Storage(
            valueClient: .makeInMemory(),
            security: .makePlaintextOnly(),
            secretPersistencePolicy: .acceptProviderOutput
        )
        let snapshots = await OpalBase.WalletSnapshotInteractor(storage: storage)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000 + fractionalSeconds)
        let category = try OpalBase.CashTokens.CategoryID(hexFromRPC: String(repeating: "ab", count: 32))
        let metadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: "Fractional Token",
            symbol: "FRACTION",
            decimals: 2,
            iconURL: nil,
            lastUpdated: timestamp,
            source: .embedded
        )
        let account = OpalBase.Account.Snapshot(
            purpose: .bip44,
            coinType: .bitcoinCash,
            accountUnhardenedIndex: 0,
            addressBook: OpalBase.Account.Snapshot.AddressBook(
                receivingEntries: [
                    .init(
                        usage: .receiving,
                        index: 0,
                        isUsed: true,
                        isReserved: false,
                        balance: 1_234,
                        lastUpdated: timestamp
                    )
                ],
                changeEntries: [],
                utxos: [],
                transactions: [
                    .init(
                        transactionHash: String(repeating: "01", count: 32),
                        height: 1,
                        fee: 100,
                        scriptHashes: [],
                        firstSeenAt: timestamp,
                        lastUpdatedAt: timestamp.addingTimeInterval(0.25),
                        status: .confirmed,
                        confirmationHeight: 1,
                        confirmedAt: timestamp.addingTimeInterval(0.5),
                        verificationStatus: .pending,
                        merkleProof: nil,
                        lastVerifiedHeight: nil,
                        lastCheckedAt: timestamp.addingTimeInterval(0.75)
                    )
                ]
            )
        )
        let snapshot = OpalBase.Wallet.Snapshot(
            purpose: .bip44,
            coinType: .bitcoinCash,
            accounts: [account],
            tokenMetadata: .init(byCategory: [category.hexForDisplay: metadata])
        )

        try await snapshots.saveSnapshot(snapshot, generation: "fractional-public-dates")
        let restored = try #require(try await snapshots.loadSnapshot(generation: "fractional-public-dates"))
        let restoredAccount = try #require(restored.accounts.first)
        let restoredTransaction = try #require(restoredAccount.addressBook.transactions.first)
        let expectedTransaction = try #require(account.addressBook.transactions.first)

        #expect(restoredAccount.addressBook.receivingEntries.first?.lastUpdated == timestamp)
        #expect(restoredTransaction.firstSeenAt == expectedTransaction.firstSeenAt)
        #expect(restoredTransaction.lastUpdatedAt == expectedTransaction.lastUpdatedAt)
        #expect(restoredTransaction.confirmedAt == expectedTransaction.confirmedAt)
        #expect(restoredTransaction.lastCheckedAt == expectedTransaction.lastCheckedAt)
        #expect(restored.tokenMetadata?.byCategory[category.hexForDisplay] == metadata)
    }

    @Test("snapshot-only persistence reads legacy ISO-8601 public timestamps")
    func snapshotOnlyPersistenceReadsLegacyISOTimestamps() async throws {
        let categoryHex = String(repeating: "ab", count: 32)
        let transactionHash = String(repeating: "01", count: 32)
        let legacySnapshotJSON = """
        {
          "purpose":2147483692,"coinType":2147483793,
          "accounts":[{
            "purpose":2147483692,"coinType":2147483793,"accountUnhardenedIndex":0,
            "addressBook":{
              "receivingEntries":[{
                "usage":"receiving","index":0,"isUsed":true,"isReserved":false,
                "balance":1234,"lastUpdated":"2023-11-14T22:13:20Z"
              }],
              "changeEntries":[],"utxos":[],
              "transactions":[{
                "transactionHash":"\(transactionHash)","height":1,"fee":100,"scriptHashes":[],
                "firstSeenAt":"2023-11-14T22:13:20Z","lastUpdatedAt":"2023-11-14T22:13:21Z",
                "status":"confirmed","confirmationHeight":1,"confirmedAt":"2023-11-14T22:13:22Z",
                "verificationStatus":"pending","lastCheckedAt":"2023-11-14T22:13:23Z"
              }]
            }
          }],
          "tokenMetadata":{"byCategory":{
            "\(categoryHex)":{
              "category":"\(categoryHex)","name":"Legacy Token","symbol":"LEGACY","decimals":2,
              "lastUpdated":"2023-11-14T22:13:20Z","source":{"embedded":{}}
            }
          }}
        }
        """
        let legacySnapshotData = Data(legacySnapshotJSON.utf8)
        let valueClient = OpalBase.Storage.ValueClient(
            valueWriter: { _, _ in },
            valueReader: { _ in legacySnapshotData },
            valueDeleter: { _ in },
            allValuesDeleter: {}
        )
        let storage = try OpalBase.Storage(
            valueClient: valueClient,
            security: .makePlaintextOnly(),
            secretPersistencePolicy: .acceptProviderOutput
        )
        let snapshots = await OpalBase.WalletSnapshotInteractor(storage: storage)

        let restored = try #require(try await snapshots.loadSnapshot(generation: "legacy-public-dates"))
        let account = try #require(restored.accounts.first)
        let transaction = try #require(account.addressBook.transactions.first)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(account.addressBook.receivingEntries.first?.lastUpdated == timestamp)
        #expect(transaction.firstSeenAt == timestamp)
        #expect(transaction.lastUpdatedAt == timestamp.addingTimeInterval(1))
        #expect(transaction.confirmedAt == timestamp.addingTimeInterval(2))
        #expect(transaction.lastCheckedAt == timestamp.addingTimeInterval(3))
        #expect(restored.tokenMetadata?.byCategory[categoryHex]?.lastUpdated == timestamp)
    }

    @Test("persistState(for:) + restore() round-trips wallet snapshots and mnemonic state")
    func persistAndRestoreWalletArtifacts() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let storage = try OpalBase.Storage(
            valueClient: valueClient,
            security: .makePlaintextOnly(),
            secretPersistencePolicy: .legacyFallbackToPlaintext
        )

        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "session-passphrase")
        let account = try await wallet.fetchAccount(at: 0)

        _ = try await account.reserveNextReceivingAddress()
        let expectedSnapshot = await wallet.makeSnapshot()

        let protectionMode = try await storage.persistState(
            for: wallet
        )
        #expect([OpalBase.Storage.Security.ProtectionMode.plaintext, .software, .secureEnclave].contains(protectionMode))

        let restoredStorage = try OpalBase.Storage(
            valueClient: valueClient,
            security: .makePlaintextOnly(),
            secretPersistencePolicy: .legacyFallbackToPlaintext
        )
        let session = await OpalBase.Storage.PersistenceSession(storage: restoredStorage)
        let restored = try await session.restore()

        let restoredWalletSnapshot = try #require(restored.walletSnapshot)
        #expect(restoredWalletSnapshot.purpose == expectedSnapshot.purpose)
        #expect(restoredWalletSnapshot.coinType == expectedSnapshot.coinType)
        #expect(restoredWalletSnapshot.accounts == expectedSnapshot.accounts)
        #expect(
            restoredWalletSnapshot.tokenMetadata?.byCategory
                == expectedSnapshot.tokenMetadata?.byCategory
        )

        let restoredMnemonic = try #require(restored.mnemonic)
        #expect(restoredMnemonic.words == AccountTestFixtures.mnemonicWords)
        #expect(restoredMnemonic.passphrase == "session-passphrase")
        #expect(restored.mnemonicProtectionMode == protectionMode)

        let reconstructedWallet = try await OpalBase.Wallet(
            mnemonic: try OpalBase.Key.Mnemonic(
                words: restoredMnemonic.words.map(OpalBase.Key.Mnemonic.Word.init)
            ),
            passphrase: restoredMnemonic.passphrase,
            from: restoredWalletSnapshot
        )
        let reconstructedAccount = try await reconstructedWallet.fetchAccount(at: 0)
        let nextReceiving = try await reconstructedAccount.selectNextEntry(for: .receiving)
        #expect(nextReceiving.derivationPath.index == 1)
    }

    @Test("restore returns an empty state for a fresh install")
    func restoreEmptyStateWhenNothingPersisted() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let storage = try OpalBase.Storage(
            valueClient: valueClient,
            security: .makePlaintextOnly(),
            secretPersistencePolicy: .legacyFallbackToPlaintext
        )
        let session = await OpalBase.Storage.PersistenceSession(storage: storage)

        let restored = try await session.restore()

        #expect(restored.walletSnapshot == nil)
        #expect(restored.mnemonic == nil)
        #expect(restored.mnemonicProtectionMode == nil)
    }

    @Test("failed staged saves leave the previous committed generation active")
    func failedStagedSaveKeepsPreviouslyCommittedState() async throws {
        let snapshotState = GenerationSnapshotPersistenceState()
        let mnemonicState = GenerationMnemonicPersistenceState()
        let session = OpalBase.Storage.PersistenceSession(
            snapshotPersistence: makeGenerationSnapshotPersistence(state: snapshotState),
            storedMnemonicPersistence: makeGenerationMnemonicPersistence(state: mnemonicState)
        )

        let initialWallet = try await AccountTestFixtures.makeWallet(passphrase: "first-passphrase")
        let initialAccount = try await initialWallet.fetchAccount(at: 0)
        _ = try await initialAccount.reserveNextReceivingAddress()

        let initialProtectionMode = try await session.save(
            wallet: initialWallet
        )
        #expect(initialProtectionMode == .plaintext)

        let replacementWallet = try await AccountTestFixtures.makeWallet(
            accountIndices: [0, 1],
            passphrase: "second-passphrase"
        )
        await mnemonicState.failNextSave()

        try await expectGenerationPersistenceSimulatedFailure {
            _ = try await session.save(
                wallet: replacementWallet
            )
        }

        let restored = try await session.restore()
        let restoredWalletSnapshot = try #require(restored.walletSnapshot)
        let restoredMnemonic = try #require(restored.mnemonic)

        #expect(restoredWalletSnapshot.accounts.count == 1)
        #expect(restoredWalletSnapshot.accounts.first?.accountUnhardenedIndex == 0)
        #expect(restoredMnemonic.passphrase == "first-passphrase")
        #expect(restored.mnemonicProtectionMode == .plaintext)
    }

    @Test("commit marker failures restore the previous generation after partial writes")
    func restorePreviouslyCommittedStateAfterCommitMarkerFailure() async throws {
        let snapshotState = GenerationSnapshotPersistenceState()
        let mnemonicState = GenerationMnemonicPersistenceState()
        let session = OpalBase.Storage.PersistenceSession(
            snapshotPersistence: makeGenerationSnapshotPersistence(state: snapshotState),
            storedMnemonicPersistence: makeGenerationMnemonicPersistence(state: mnemonicState)
        )

        let initialWallet = try await AccountTestFixtures.makeWallet(passphrase: "first-passphrase")
        let initialAccount = try await initialWallet.fetchAccount(at: 0)
        _ = try await initialAccount.reserveNextReceivingAddress()

        _ = try await session.save(
            wallet: initialWallet
        )
        let initialCommittedGeneration = try #require(await snapshotState.loadCommittedGeneration())

        let replacementWallet = try await AccountTestFixtures.makeWallet(
            accountIndices: [0, 1],
            passphrase: "second-passphrase"
        )
        await snapshotState.failNextCommittedGenerationSaveAfterMutation()

        try await expectGenerationPersistenceSimulatedFailure {
            _ = try await session.save(
                wallet: replacementWallet
            )
        }

        #expect(await snapshotState.loadCommittedGeneration() == initialCommittedGeneration)

        let restored = try await session.restore()
        let restoredWalletSnapshot = try #require(restored.walletSnapshot)
        let restoredMnemonic = try #require(restored.mnemonic)

        #expect(restoredWalletSnapshot.accounts.count == 1)
        #expect(restoredWalletSnapshot.accounts.first?.accountUnhardenedIndex == 0)
        #expect(restoredMnemonic.passphrase == "first-passphrase")
        #expect(restored.mnemonicProtectionMode == .plaintext)
    }

    @Test("rollback failures preserve artifacts for the still-committed staged generation")
    func preserveStagedArtifactsAfterCommitMarkerRollbackFailure() async throws {
        let snapshotState = GenerationSnapshotPersistenceState()
        let mnemonicState = GenerationMnemonicPersistenceState()
        let session = OpalBase.Storage.PersistenceSession(
            snapshotPersistence: makeGenerationSnapshotPersistence(state: snapshotState),
            storedMnemonicPersistence: makeGenerationMnemonicPersistence(state: mnemonicState)
        )

        let initialWallet = try await AccountTestFixtures.makeWallet(passphrase: "first-passphrase")
        _ = try await session.save(
            wallet: initialWallet
        )
        let initialCommittedGeneration = try #require(await snapshotState.loadCommittedGeneration())

        let replacementWallet = try await AccountTestFixtures.makeWallet(
            accountIndices: [0, 1],
            passphrase: "second-passphrase"
        )
        await snapshotState.failNextCommittedGenerationSaveAfterMutation()
        await snapshotState.failNextCommittedGenerationSaveBeforeMutation()

        try await expectGenerationPersistenceSimulatedFailure {
            _ = try await session.save(
                wallet: replacementWallet
            )
        }

        let stagedGeneration = try #require(await snapshotState.loadCommittedGeneration())
        #expect(stagedGeneration != initialCommittedGeneration)

        let restored = try await session.restore()
        let restoredWalletSnapshot = try #require(restored.walletSnapshot)
        let restoredMnemonic = try #require(restored.mnemonic)

        #expect(restoredWalletSnapshot.accounts.count == 2)
        #expect(restoredMnemonic.passphrase == "second-passphrase")
        #expect(restored.mnemonicProtectionMode == .plaintext)
    }

    @Test("manual persistence sessions tolerate configured recoverable mnemonic load failures")
    func manualPersistenceSessionToleratesConfiguredRecoverableMnemonicLoadFailures() async throws {
        let snapshotState = GenerationSnapshotPersistenceState()
        let mnemonicState = GenerationMnemonicPersistenceState()
        let storedMnemonicPersistence = OpalBase.Storage.StoredMnemonicPersistence(
            secretPersistencePolicy: .legacyFallbackToPlaintext,
            saveMnemonic: { mnemonic, generation, policy in
                try await mnemonicState.saveMnemonic(
                    mnemonic,
                    generation: generation,
                    policy: policy
                )
            },
            loadMnemonicState: { _ in
                throw ManualPersistenceRecoverableLoadFailure.mnemonicUnavailable
            },
            deleteMnemonic: { generation in
                try await mnemonicState.deleteMnemonic(generation: generation)
            },
            recoverableLoadFailure: { error in
                error as? ManualPersistenceRecoverableLoadFailure == .mnemonicUnavailable
            }
        )
        let session = OpalBase.Storage.PersistenceSession(
            snapshotPersistence: makeGenerationSnapshotPersistence(state: snapshotState),
            storedMnemonicPersistence: storedMnemonicPersistence
        )
        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "manual-recoverable-load")

        _ = try await session.save(
            wallet: wallet
        )
        let restored = try await session.restore()

        #expect(restored.walletSnapshot != nil)
        #expect(restored.mnemonic == nil)
        #expect(restored.mnemonicProtectionMode == nil)
    }

    @Test("failed wipes do not expose partial committed state on restore")
    func failedWipeDoesNotExposePartialCommittedState() async throws {
        let snapshotState = GenerationSnapshotPersistenceState()
        let mnemonicState = GenerationMnemonicPersistenceState()
        let resetProbe = ProtectedMaterialResetProbe()
        let session = OpalBase.Storage.PersistenceSession(
            snapshotPersistence: makeGenerationSnapshotPersistence(state: snapshotState),
            storedMnemonicPersistence: makeGenerationMnemonicPersistence(state: mnemonicState),
            protectedMaterialReset: {
                resetProbe.recordReset()
            }
        )

        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "wipe-failure")
        _ = try await session.save(
            wallet: wallet
        )
        await mnemonicState.failNextDelete()

        try await expectGenerationPersistenceSimulatedFailure {
            try await session.wipe()
        }

        let restored = try await session.restore()

        #expect(restored.walletSnapshot == nil)
        #expect(restored.mnemonic == nil)
        #expect(restored.mnemonicProtectionMode == nil)
        #expect(await snapshotState.loadCommittedGeneration() == nil)
        #expect(resetProbe.wasReset)
    }

    func makeGenerationSnapshotPersistence(
        state: GenerationSnapshotPersistenceState
    ) -> OpalBase.Storage.SnapshotPersistence {
        OpalBase.Storage.SnapshotPersistence(
            saveWalletSnapshot: { snapshot, generation in
                await state.saveWalletSnapshot(snapshot, generation: generation)
            },
            loadWalletSnapshot: { generation in
                await state.loadWalletSnapshot(generation: generation)
            },
            deleteWalletSnapshot: { generation in
                await state.deleteWalletSnapshot(generation: generation)
            },
            saveCommittedGeneration: { generation in
                try await state.saveCommittedGeneration(generation)
            },
            loadCommittedGeneration: {
                await state.loadCommittedGeneration()
            },
            deleteCommittedGeneration: {
                await state.deleteCommittedGeneration()
            }
        )
    }

    private func expectGenerationPersistenceSimulatedFailure(
        _ operation: () async throws -> Void
    ) async throws {
        do {
            try await operation()
        } catch GenerationPersistenceError.simulatedFailure {
            return
        } catch {
            throw GenerationPersistenceErrorCaptureFailure.unexpected(String(describing: error))
        }
        throw GenerationPersistenceErrorCaptureFailure.didNotThrow
    }

    func makeGenerationMnemonicPersistence(
        state: GenerationMnemonicPersistenceState
    ) -> OpalBase.Storage.StoredMnemonicPersistence {
        OpalBase.Storage.StoredMnemonicPersistence(
            secretPersistencePolicy: .legacyFallbackToPlaintext,
            saveMnemonic: { mnemonic, generation, policy in
                try await state.saveMnemonic(
                    mnemonic,
                    generation: generation,
                    policy: policy
                )
            },
            loadMnemonicState: { generation in
                await state.loadMnemonicState(generation: generation)
            },
            deleteMnemonic: { generation in
                try await state.deleteMnemonic(generation: generation)
            }
        )
    }
}

private enum ManualPersistenceRecoverableLoadFailure: Swift.Error, Equatable {
    case mnemonicUnavailable
}
