import Foundation
import Testing
@testable import OpalBase

@Suite("Storage persistence and wallet workflows")
struct StoragePersistenceValidator {
    @Test("storage uses canonical keys for wallet artifacts")
    func verifyStorageUsesCanonicalKeys() {
        let accountIdentifier = Data("account-0".utf8)
        let encodedIdentifier = accountIdentifier.base64EncodedString()

        #expect(Storage.Key.walletSnapshot.rawValue == "wallet.snapshot")
        #expect(Storage.Key.accountSnapshot(accountIdentifier).rawValue == "account.snapshot.\(encodedIdentifier)")
        #expect(Storage.Key.addressBookSnapshot(accountIdentifier).rawValue == "address-book.snapshot.\(encodedIdentifier)")
        #expect(Storage.Key.mnemonicCiphertext.rawValue == "mnemonic.enc")
    }

    @Test("mnemonic persistence does not require retaining a wallet instance")
    func persistMnemonicWithoutWalletRetention() async throws {
        let valueStore = Storage.ValueStore.makeInMemory()
        let storage = try Storage(valueStore: valueStore)

        let mnemonic = Storage.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: "long form passphrase"
        )

        let protectionMode = try await storage.saveMnemonic(mnemonic, fallbackToPlaintext: true)
        #expect([Storage.Security.ProtectionMode.plaintext, .software, .secureEnclave].contains(protectionMode))

        let restoredStorage = try Storage(valueStore: valueStore)
        let restored = try await restoredStorage.loadMnemonicState()

        #expect(restored?.mnemonic.words == mnemonic.words)
        #expect(restored?.mnemonic.passphrase == mnemonic.passphrase)
        #expect(restored?.protectionMode == protectionMode)
    }
}
