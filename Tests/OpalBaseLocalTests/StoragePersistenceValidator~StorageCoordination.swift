// StoragePersistenceValidator~StorageCoordination.swift

import Foundation
import Testing
@testable import OpalBase

extension StoragePersistenceValidator {
    @Test(
        "direct storage primitives wait for coordinated persistence operations",
        .timeLimit(.minutes(1))
    )
    func serializeDirectStoragePrimitivesWithPersistenceOperations() async throws {
        let storage = try OpalBase.Storage(valueClient: .makeInMemory())
        let persistence = await storage.makeSnapshotPersistence()
        let barrier = PersistenceOperationBarrierState()
        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "storage-primitives")
        let snapshot = await wallet.makeSnapshot()
        let mnemonic = OpalBase.Storage.StoredMnemonic(
            words: AccountTestFixtures.mnemonicWords,
            passphrase: "storage-primitives"
        )
        let operationState = PersistencePrimitiveOperationState()
        let holdingOperation = Task {
            await persistence.performExclusively {
                await barrier.holdFirstOperation()
            }
        }
        await barrier.waitUntilFirstOperationHoldsAccess()

        let snapshotSave = Task {
            await operationState.recordOperationStart()
            try await storage.saveWalletSnapshot(snapshot)
            await operationState.recordOperationCompletion()
        }
        let snapshotLoad = Task {
            await operationState.recordOperationStart()
            _ = try await storage.loadWalletSnapshot()
            await operationState.recordOperationCompletion()
        }
        let mnemonicSave = Task {
            await operationState.recordOperationStart()
            _ = try await storage.saveMnemonic(
                mnemonic,
                policy: .acceptProviderOutput
            )
            await operationState.recordOperationCompletion()
        }
        let mnemonicLoad = Task {
            await operationState.recordOperationStart()
            _ = try await storage.loadMnemonicState()
            await operationState.recordOperationCompletion()
        }
        let mnemonicDelete = Task {
            await operationState.recordOperationStart()
            try await storage.deleteMnemonic()
            await operationState.recordOperationCompletion()
        }
        let customDelete = Task {
            await operationState.recordOperationStart()
            try await storage.delete(key: "custom")
            await operationState.recordOperationCompletion()
        }

        while await operationState.startedOperationCount != 6 {
            await Task.yield()
        }
        try await Task.sleep(for: .milliseconds(25))
        #expect(await operationState.completedOperationCount == 0)

        await barrier.releaseFirstOperation()
        await holdingOperation.value
        try await snapshotSave.value
        try await snapshotLoad.value
        try await mnemonicSave.value
        try await mnemonicLoad.value
        try await mnemonicDelete.value
        try await customDelete.value
        #expect(await operationState.completedOperationCount == 6)
    }
}
