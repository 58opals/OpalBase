// StoragePersistenceValidator~SnapshotPersistence.swift

import Foundation
import Testing
@testable import OpalBase

extension StoragePersistenceValidator {
    @Test("persistState(for:) + restore() round-trips wallet snapshots and mnemonic state")
    func persistAndRestoreWalletArtifacts() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let storage = try OpalBase.Storage(valueClient: valueClient)

        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "session-passphrase")
        let account = try await wallet.fetchAccount(at: 0)

        _ = try await account.reserveNextReceivingAddress()
        let expectedSnapshot = await wallet.makeSnapshot()

        let protectionMode = try await storage.persistState(for: wallet)
        #expect([OpalBase.Storage.Security.ProtectionMode.plaintext, .software, .secureEnclave].contains(protectionMode))

        let restoredStorage = try OpalBase.Storage(valueClient: valueClient)
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
        let storage = try OpalBase.Storage(valueClient: valueClient)
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

        let initialProtectionMode = try await session.save(wallet: initialWallet)
        #expect(initialProtectionMode == .plaintext)

        let replacementWallet = try await AccountTestFixtures.makeWallet(
            accountIndices: [0, 1],
            passphrase: "second-passphrase"
        )
        await mnemonicState.failNextSave()

        try await expectGenerationPersistenceSimulatedFailure {
            _ = try await session.save(wallet: replacementWallet)
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

        _ = try await session.save(wallet: initialWallet)
        let initialCommittedGeneration = try #require(await snapshotState.loadCommittedGeneration())

        let replacementWallet = try await AccountTestFixtures.makeWallet(
            accountIndices: [0, 1],
            passphrase: "second-passphrase"
        )
        await snapshotState.failNextCommittedGenerationSaveAfterMutation()

        try await expectGenerationPersistenceSimulatedFailure {
            _ = try await session.save(wallet: replacementWallet)
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
        _ = try await session.save(wallet: initialWallet)
        let initialCommittedGeneration = try #require(await snapshotState.loadCommittedGeneration())

        let replacementWallet = try await AccountTestFixtures.makeWallet(
            accountIndices: [0, 1],
            passphrase: "second-passphrase"
        )
        await snapshotState.failNextCommittedGenerationSaveAfterMutation()
        await snapshotState.failNextCommittedGenerationSaveBeforeMutation()

        try await expectGenerationPersistenceSimulatedFailure {
            _ = try await session.save(wallet: replacementWallet)
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
            saveMnemonic: { mnemonic, generation, fallbackToPlaintext in
                try await mnemonicState.saveMnemonic(
                    mnemonic,
                    generation: generation,
                    fallbackToPlaintext: fallbackToPlaintext
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

        _ = try await session.save(wallet: wallet)
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
        _ = try await session.save(wallet: wallet)
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
            saveMnemonic: { mnemonic, generation, fallbackToPlaintext in
                try await state.saveMnemonic(
                    mnemonic,
                    generation: generation,
                    fallbackToPlaintext: fallbackToPlaintext
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
