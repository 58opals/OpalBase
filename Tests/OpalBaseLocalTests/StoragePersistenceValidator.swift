// StoragePersistenceValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Storage persistence and wallet workflows", .tags(.unit, .wallet))
struct StoragePersistenceValidator {
    @Test("storage uses canonical keys for wallet artifacts")
    func verifyStorageUsesCanonicalKeys() {
        let accountIdentifier = Data("account-0".utf8)
        let encodedIdentifier = accountIdentifier.base64EncodedString()
        let generation = "test-generation"

        #expect(OpalBase.Storage.Key.walletSnapshot.rawValue == "wallet.snapshot")
        #expect(OpalBase.Storage.Key.walletSnapshotGeneration(generation).rawValue == "wallet.snapshot.\(generation)")
        #expect(OpalBase.Storage.Key.walletSnapshotCommittedGeneration.rawValue == "wallet.snapshot.committed")
        #expect(OpalBase.Storage.Key.accountSnapshot(accountIdentifier).rawValue == "account.snapshot.\(encodedIdentifier)")
        #expect(OpalBase.Storage.Key.addressBookSnapshot(accountIdentifier).rawValue == "address-book.snapshot.\(encodedIdentifier)")
        #expect(OpalBase.Storage.Key.mnemonicCiphertext.rawValue == "mnemonic.enc")
        #expect(OpalBase.Storage.Key.mnemonicCiphertextGeneration(generation).rawValue == "mnemonic.enc.\(generation)")
    }

    @Test("mnemonic persistence does not require retaining a wallet instance")
    func persistMnemonicWithoutWalletRetention() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let storage = try OpalBase.Storage(valueClient: valueClient)

        let mnemonic = OpalBase.Storage.StoredMnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: "long form passphrase"
        )

        let protectionMode = try await storage.saveMnemonic(mnemonic, fallbackToPlaintext: true)
        #expect([OpalBase.Storage.Security.ProtectionMode.plaintext, .software, .secureEnclave].contains(protectionMode))

        let restoredStorage = try OpalBase.Storage(valueClient: valueClient)
        let restored = try await restoredStorage.loadMnemonicState()

        #expect(restored?.mnemonic.words == mnemonic.words)
        #expect(restored?.mnemonic.passphrase == mnemonic.passphrase)
        #expect(restored?.protectionMode == protectionMode)
    }
}
