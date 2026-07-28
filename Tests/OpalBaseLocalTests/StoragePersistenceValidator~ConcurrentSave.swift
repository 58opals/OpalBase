// StoragePersistenceValidator~ConcurrentSave.swift

import Foundation
import Synchronization
import Testing
@testable import OpalBase

extension StoragePersistenceValidator {
    @Test("concurrent save rollback preserves the later committed state")
    func preserveLaterCommittedStateWhenConcurrentSaveRollsBack() async throws {
        let snapshotState = GenerationSnapshotPersistenceState()
        let mnemonicState = GenerationMnemonicPersistenceState()
        let snapshotPersistence = makeGenerationSnapshotPersistence(state: snapshotState)
        let mnemonicPersistence = makeGenerationMnemonicPersistence(state: mnemonicState)
        let firstSession = OpalBase.Storage.PersistenceSession(
            snapshotPersistence: snapshotPersistence,
            storedMnemonicPersistence: mnemonicPersistence
        )
        let secondSession = OpalBase.Storage.PersistenceSession(
            snapshotPersistence: snapshotPersistence,
            storedMnemonicPersistence: mnemonicPersistence
        )
        let initialWallet = try await AccountTestFixtures.makeWallet(passphrase: "initial")
        _ = try await firstSession.save(wallet: initialWallet)
        let initialGeneration = try #require(await snapshotState.loadCommittedGeneration())

        let firstReplacement = try await AccountTestFixtures.makeWallet(
            accountIndices: [0, 1],
            passphrase: "first-replacement"
        )
        let secondReplacement = try await AccountTestFixtures.makeWallet(
            accountIndices: [0, 1, 2],
            passphrase: "second-replacement"
        )
        await snapshotState.blockNextWalletSnapshotSave()

        let firstSave = Task {
            do {
                _ = try await firstSession.save(wallet: firstReplacement)
                return false
            } catch GenerationPersistenceError.simulatedFailure {
                return true
            } catch {
                return false
            }
        }
        await snapshotState.waitUntilWalletSnapshotSaveBlocks()

        let hasCompetingSaveStarted = Mutex(false)
        let secondSave = Task {
            hasCompetingSaveStarted.withLock { $0 = true }
            return try await secondSession.save(wallet: secondReplacement)
        }
        while !hasCompetingSaveStarted.withLock({ $0 }) {
            await Task.yield()
        }
        try await Task.sleep(for: .milliseconds(50))

        #expect(await snapshotState.loadCommittedGeneration() == initialGeneration)
        await snapshotState.failNextCommittedGenerationSaveAfterMutation()
        await snapshotState.releaseBlockedWalletSnapshotSave()

        #expect(await firstSave.value)
        #expect(try await secondSave.value == .plaintext)

        let restored = try await secondSession.restore()
        #expect(restored.walletSnapshot?.accounts.count == 3)
        #expect(restored.mnemonic?.passphrase == "second-replacement")
    }

    @Test(
        "progress callbacks can reenter after exclusive persistence work",
        .timeLimit(.minutes(1))
    )
    func allowProgressCallbacksToReenterAfterExclusivePersistenceWork() async throws {
        let storage = try OpalBase.Storage(valueClient: .makeInMemory())
        let snapshotPersistence = await storage.makeSnapshotPersistence()
        let mnemonicPersistence = await storage.makeStoredMnemonicPersistence()
        let reentrantSession = OpalBase.Storage.PersistenceSession(
            snapshotPersistence: snapshotPersistence,
            storedMnemonicPersistence: mnemonicPersistence
        )
        let restoredPassphrase = Mutex<String?>(nil)
        let progressEvents = Mutex<[OpalBase.Storage.PersistenceSession.Progress]>(.init())
        let session = OpalBase.Storage.PersistenceSession(
            snapshotPersistence: snapshotPersistence,
            storedMnemonicPersistence: mnemonicPersistence,
            progressHandler: { progress in
                progressEvents.withLock { $0.append(progress) }
                guard case .savedWalletSnapshot = progress else {
                    return
                }

                let restored = try? await reentrantSession.restore()
                restoredPassphrase.withLock { $0 = restored?.mnemonic?.passphrase }
            }
        )
        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "reentrant-progress")

        let protectionMode = try await session.save(wallet: wallet)

        #expect(protectionMode == .plaintext)
        #expect(restoredPassphrase.withLock { $0 } == "reentrant-progress")
        let events = progressEvents.withLock { $0 }
        #expect(events.first == .beganSave)
        #expect(events.last == .finishedSave(mode: .plaintext))
        #expect(events.count == 5)
    }

    @Test("failed saves deliver completed progress events in order")
    func deliverCompletedProgressEventsAfterSaveFailure() async throws {
        let snapshotState = GenerationSnapshotPersistenceState()
        let mnemonicState = GenerationMnemonicPersistenceState()
        let progressEvents = Mutex<[OpalBase.Storage.PersistenceSession.Progress]>(.init())
        let session = OpalBase.Storage.PersistenceSession(
            snapshotPersistence: makeGenerationSnapshotPersistence(state: snapshotState),
            storedMnemonicPersistence: makeGenerationMnemonicPersistence(state: mnemonicState),
            progressHandler: { progress in
                progressEvents.withLock { $0.append(progress) }
            }
        )
        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "partial-progress")
        await mnemonicState.failNextSave()

        do {
            _ = try await session.save(wallet: wallet)
            Issue.record("Expected the mnemonic save to fail.")
        } catch GenerationPersistenceError.simulatedFailure {
        }

        let events = progressEvents.withLock { $0 }
        #expect(events.first == .beganSave)
        #expect(events.count == 2)
        guard events.count == 2 else {
            return
        }
        guard case .savedWalletSnapshot = events[1] else {
            Issue.record("Expected saved-wallet progress before the failure.")
            return
        }
    }
}
