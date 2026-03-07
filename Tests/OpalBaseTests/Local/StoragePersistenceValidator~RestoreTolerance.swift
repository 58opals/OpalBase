// StoragePersistenceValidator~RestoreTolerance.swift

import Foundation
import Testing
@testable import OpalBase

extension StoragePersistenceValidator {
    @Test("restore tolerates missing account/address book snapshots while still restoring wallet snapshot")
    func tolerateMissingAccountSnapshotsDuringRestore() async throws {
        let valueStore = OpalBase.Storage.ValueRepository.makeInMemory()
        let storage = try OpalBase.Storage(valueStore: valueStore)

        let mnemonic = try OpalBase.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: "passphrase"
        )
        let wallet = OpalBase.Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)

        let account = try await wallet.fetchAccount(at: 0)
        let accountIdentifier = await account.id

        _ = try await storage.persistState(for: wallet)

        try await storage.removeValue(for: .accountSnapshot(accountIdentifier))
        try await storage.removeValue(for: .addressBookSnapshot(accountIdentifier))

        let session = OpalBase.Storage.PersistenceSessionModel(storage: storage)
        let restored = try await session.restore(accountIdentifiers: [accountIdentifier])

        #expect(restored.walletSnapshot != nil)
        #expect(restored.accountSnapshots.isEmpty)
        #expect(restored.addressBookSnapshots.isEmpty)
        #expect(restored.mnemonic != nil)
    }

    @Test("restore tolerates missing mnemonic ciphertext (e.g., keychain cleared) while still restoring snapshots")
    func tolerateMissingMnemonicCiphertextDuringRestore() async throws {
        let valueStore = OpalBase.Storage.ValueRepository.makeInMemory()
        let storage = try OpalBase.Storage(valueStore: valueStore)

        let mnemonic = try OpalBase.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: "passphrase"
        )
        let wallet = OpalBase.Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)

        let account = try await wallet.fetchAccount(at: 0)
        let accountIdentifier = await account.id

        _ = try await storage.persistState(for: wallet)

        try await storage.removeValue(for: .mnemonicCiphertext)

        let session = OpalBase.Storage.PersistenceSessionModel(storage: storage)
        let restored = try await session.restore(accountIdentifiers: [accountIdentifier])

        #expect(restored.walletSnapshot != nil)
        #expect(restored.accountSnapshots[accountIdentifier] != nil)
        #expect(restored.addressBookSnapshots[accountIdentifier] != nil)
        #expect(restored.mnemonic == nil)
        #expect(restored.mnemonicProtectionMode == nil)
    }

    @Test("wipeAll removes persisted wallet artifacts")
    func removePersistedArtifactsWithWipeAll() async throws {
        let valueStore = OpalBase.Storage.ValueRepository.makeInMemory()
        let storage = try OpalBase.Storage(valueStore: valueStore)

        let mnemonic = try OpalBase.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: "wipe-passphrase"
        )
        let wallet = OpalBase.Wallet(mnemonic: mnemonic)
        try await wallet.addAccount(unhardenedIndex: 0)

        let account = try await wallet.fetchAccount(at: 0)
        let accountIdentifier = await account.id

        _ = try await storage.persistState(for: wallet)
        try await storage.wipeAll()

        let session = OpalBase.Storage.PersistenceSessionModel(storage: storage)
        let restored = try await session.restore(accountIdentifiers: [accountIdentifier])

        #expect(restored.walletSnapshot == nil)
        #expect(restored.accountSnapshots.isEmpty)
        #expect(restored.addressBookSnapshots.isEmpty)
        #expect(restored.mnemonic == nil)
        #expect(restored.mnemonicProtectionMode == nil)
    }
}

