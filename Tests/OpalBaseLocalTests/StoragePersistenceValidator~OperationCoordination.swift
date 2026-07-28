// StoragePersistenceValidator~OperationCoordination.swift

import Foundation
import Testing
@testable import OpalBase

extension StoragePersistenceValidator {
    @Test("snapshot persistence values from one storage serialize operations")
    func serializeOperationsAcrossStorageSnapshotPersistenceValues() async throws {
        let storage = try OpalBase.Storage(valueClient: .makeInMemory())
        let firstPersistence = await storage.makeSnapshotPersistence()
        let secondPersistence = await storage.makeSnapshotPersistence()

        try await expectSharedExclusiveAccess(
            firstPersistence,
            secondPersistence
        )
    }

    @Test("snapshot persistence copies serialize operations")
    func serializeOperationsAcrossSnapshotPersistenceCopies() async throws {
        let persistence = makeGenerationSnapshotPersistence(
            state: GenerationSnapshotPersistenceState()
        )

        try await expectSharedExclusiveAccess(persistence, persistence)
    }

    @Test(
        "public persistence facades wait for session transactions",
        .timeLimit(.minutes(1))
    )
    func serializePublicPersistenceFacadesWithSessionTransactions() async throws {
        let snapshotState = GenerationSnapshotPersistenceState()
        let mnemonicState = GenerationMnemonicPersistenceState()
        let snapshotPersistence = makeGenerationSnapshotPersistence(state: snapshotState)
        let mnemonicPersistence = makeGenerationMnemonicPersistence(state: mnemonicState)
        let session = OpalBase.Storage.PersistenceSession(
            snapshotPersistence: snapshotPersistence,
            storedMnemonicPersistence: mnemonicPersistence
        )
        let snapshotInteractor = OpalBase.WalletSnapshotInteractor(
            snapshotPersistence: snapshotPersistence
        )
        let sessionWallet = try await AccountTestFixtures.makeWallet(passphrase: "session")
        let publicWallet = try await AccountTestFixtures.makeWallet(
            accountIndices: [0, 1],
            passphrase: "public"
        )
        let publicSnapshot = await publicWallet.makeSnapshot()
        let publicMnemonic = OpalBase.Storage.StoredMnemonic(
            words: AccountTestFixtures.mnemonicWords,
            passphrase: "public"
        )
        let operationState = PersistencePrimitiveOperationState()

        await snapshotState.blockNextWalletSnapshotSave()
        let sessionSave = Task {
            try await session.save(wallet: sessionWallet)
        }
        await snapshotState.waitUntilWalletSnapshotSaveBlocks()

        let markerSave = Task {
            await operationState.recordOperationStart()
            try await snapshotInteractor.saveCommittedGeneration("public-marker")
            await operationState.recordOperationCompletion()
        }
        let snapshotSave = Task {
            await operationState.recordOperationStart()
            try await snapshotInteractor.saveSnapshot(
                publicSnapshot,
                generation: "public-snapshot"
            )
            await operationState.recordOperationCompletion()
        }
        let mnemonicSave = Task {
            await operationState.recordOperationStart()
            _ = try await mnemonicPersistence.saveMnemonic(
                publicMnemonic,
                generation: "public-mnemonic",
                policy: .acceptProviderOutput
            )
            await operationState.recordOperationCompletion()
        }

        while await operationState.startedOperationCount != 3 {
            await Task.yield()
        }
        try await Task.sleep(for: .milliseconds(25))

        #expect(await operationState.completedOperationCount == 0)
        #expect(await snapshotState.loadCommittedGeneration() == nil)
        #expect(await snapshotState.loadWalletSnapshot(generation: "public-snapshot") == nil)
        #expect(await mnemonicState.loadMnemonicState(generation: "public-mnemonic") == nil)

        await snapshotState.releaseBlockedWalletSnapshotSave()
        #expect(try await sessionSave.value == .plaintext)
        try await markerSave.value
        try await snapshotSave.value
        try await mnemonicSave.value

        #expect(await snapshotState.loadCommittedGeneration() == "public-marker")
        #expect(await snapshotState.loadWalletSnapshot(generation: "public-snapshot") != nil)
        #expect(
            await mnemonicState.loadMnemonicState(generation: "public-mnemonic")?
                .mnemonic.passphrase == "public"
        )
    }

    @Test("wipeAll serializes with persistence operations")
    func serializeWipeAllWithPersistenceOperations() async throws {
        let storage = try OpalBase.Storage(valueClient: .makeInMemory())
        let persistence = await storage.makeSnapshotPersistence()
        let barrier = PersistenceOperationBarrierState()
        let holdingOperation = Task {
            await persistence.performExclusively {
                await barrier.holdFirstOperation()
            }
        }
        await barrier.waitUntilFirstOperationHoldsAccess()

        let wipeOperation = Task {
            await barrier.recordSecondOperationAttempt()
            try await storage.wipeAll()
            await barrier.recordSecondOperationCompletion()
        }
        await barrier.waitUntilSecondOperationAttemptsAccess()
        try await Task.sleep(for: .milliseconds(25))

        #expect(!(await barrier.hasSecondOperationCompleted))
        await barrier.releaseFirstOperation()
        await holdingOperation.value
        try await wipeOperation.value
        #expect(await barrier.hasSecondOperationCompleted)
    }

    private func expectSharedExclusiveAccess(
        _ firstPersistence: OpalBase.Storage.SnapshotPersistence,
        _ secondPersistence: OpalBase.Storage.SnapshotPersistence
    ) async throws {
        let barrier = PersistenceOperationBarrierState()
        let holdingOperation = Task {
            await firstPersistence.performExclusively {
                await barrier.holdFirstOperation()
            }
        }
        await barrier.waitUntilFirstOperationHoldsAccess()

        let competingOperation = Task {
            await barrier.recordSecondOperationAttempt()
            await secondPersistence.performExclusively {
                await barrier.recordSecondOperationCompletion()
            }
        }
        await barrier.waitUntilSecondOperationAttemptsAccess()
        try await Task.sleep(for: .milliseconds(25))

        #expect(!(await barrier.hasSecondOperationCompleted))
        await barrier.releaseFirstOperation()
        await holdingOperation.value
        await competingOperation.value
        #expect(await barrier.hasSecondOperationCompleted)
    }
}
