// StoragePersistenceValidator~RestoreTolerance.swift

import Foundation
import Testing
@testable import OpalBase

extension StoragePersistenceValidator {
    @Test("restore tolerates a missing committed wallet snapshot while still restoring mnemonic state")
    func tolerateMissingWalletSnapshotDuringRestore() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let storage = try OpalBase.Storage(valueClient: valueClient)

        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "passphrase")

        _ = try await storage.persistState(for: wallet)

        let committedGeneration = try #require(
            try await storage.loadCommittedWalletSnapshotGeneration()
        )
        try await storage.deleteWalletSnapshot(generation: committedGeneration)

        let session = OpalBase.Storage.PersistenceSession(storage: storage)
        let restored = try await session.restore()

        #expect(restored.walletSnapshot == nil)
        #expect(restored.mnemonic != nil)
    }

    @Test("restore tolerates missing mnemonic ciphertext (e.g., keychain cleared) while still restoring snapshots")
    func tolerateMissingMnemonicCiphertextDuringRestore() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let storage = try OpalBase.Storage(valueClient: valueClient)

        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "passphrase")

        _ = try await storage.persistState(for: wallet)

        let committedGeneration = try #require(
            try await storage.loadCommittedWalletSnapshotGeneration()
        )
        try await storage.deleteMnemonic(generation: committedGeneration)

        let session = OpalBase.Storage.PersistenceSession(storage: storage)
        let restored = try await session.restore()

        #expect(restored.walletSnapshot != nil)
        #expect(restored.mnemonic == nil)
        #expect(restored.mnemonicProtectionMode == nil)
    }

    @Test("wipeAll removes persisted wallet artifacts")
    func removePersistedArtifactsWithWipeAll() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let storage = try OpalBase.Storage(valueClient: valueClient)

        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "wipe-passphrase")

        _ = try await storage.persistState(for: wallet)
        try await storage.wipeAll()

        let session = OpalBase.Storage.PersistenceSession(storage: storage)
        let restored = try await session.restore()

        #expect(restored.walletSnapshot == nil)
        #expect(restored.mnemonic == nil)
        #expect(restored.mnemonicProtectionMode == nil)
    }
}
