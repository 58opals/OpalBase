// StoragePersistenceValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("StorageActor persistence and wallet workflows", .tags(.unit, .wallet))
struct StoragePersistenceValidator {
    @Test("storage uses canonical keys for wallet artifacts")
    func verifyStorageUsesCanonicalKeys() {
        let accountIdentifier = Data("account-0".utf8)
        let encodedIdentifier = accountIdentifier.base64EncodedString()

        #expect(StorageActor.KeyModel.walletSnapshot.rawValue == "wallet.snapshot")
        #expect(StorageActor.KeyModel.accountSnapshot(accountIdentifier).rawValue == "account.snapshot.\(encodedIdentifier)")
        #expect(StorageActor.KeyModel.addressBookSnapshot(accountIdentifier).rawValue == "address-book.snapshot.\(encodedIdentifier)")
        #expect(StorageActor.KeyModel.mnemonicCiphertext.rawValue == "mnemonic.enc")
    }

    @Test("mnemonic persistence does not require retaining a wallet instance")
    func persistMnemonicWithoutWalletRetention() async throws {
        let valueStore = StorageActor.ValueRepository.makeInMemory()
        let storage = try StorageActor(valueStore: valueStore)

        let mnemonic = StorageActor.MnemonicModel(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: "long form passphrase"
        )

        let protectionMode = try await storage.saveMnemonic(mnemonic, fallbackToPlaintext: true)
        #expect([StorageActor.SecurityModel.ProtectionMode.plaintext, .software, .secureEnclave].contains(protectionMode))

        let restoredStorage = try StorageActor(valueStore: valueStore)
        let restored = try await restoredStorage.loadMnemonicState()

        #expect(restored?.mnemonic.words == mnemonic.words)
        #expect(restored?.mnemonic.passphrase == mnemonic.passphrase)
        #expect(restored?.protectionMode == protectionMode)
    }
}

