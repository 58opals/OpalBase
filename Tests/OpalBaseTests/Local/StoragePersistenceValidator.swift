// StoragePersistenceValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Storage persistence and wallet workflows", .tags(.unit, .wallet))
struct StoragePersistenceValidator {
    @Test("storage uses canonical keys for wallet artifacts")
    func verifyStorageUsesCanonicalKeys() {
        let accountIdentifier = Data("account-0".utf8)
        let encodedIdentifier = accountIdentifier.base64EncodedString()

        #expect(OpalBase.Storage.KeyModel.walletSnapshot.rawValue == "wallet.snapshot")
        #expect(OpalBase.Storage.KeyModel.accountSnapshot(accountIdentifier).rawValue == "account.snapshot.\(encodedIdentifier)")
        #expect(OpalBase.Storage.KeyModel.addressBookSnapshot(accountIdentifier).rawValue == "address-book.snapshot.\(encodedIdentifier)")
        #expect(OpalBase.Storage.KeyModel.mnemonicCiphertext.rawValue == "mnemonic.enc")
    }

    @Test("mnemonic persistence does not require retaining a wallet instance")
    func persistMnemonicWithoutWalletRetention() async throws {
        let valueStore = OpalBase.Storage.ValueRepository.makeInMemory()
        let storage = try OpalBase.Storage(valueStore: valueStore)

        let mnemonic = OpalBase.Storage.Mnemonic(
            words: [
                "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
                "abandon", "abandon", "abandon", "abandon", "abandon", "about"
            ],
            passphrase: "long form passphrase"
        )

        let protectionMode = try await storage.saveMnemonic(mnemonic, fallbackToPlaintext: true)
        #expect([OpalBase.Storage.SecurityModel.ProtectionMode.plaintext, .software, .secureEnclave].contains(protectionMode))

        let restoredStorage = try OpalBase.Storage(valueStore: valueStore)
        let restored = try await restoredStorage.loadMnemonicState()

        #expect(restored?.mnemonic.words == mnemonic.words)
        #expect(restored?.mnemonic.passphrase == mnemonic.passphrase)
        #expect(restored?.protectionMode == protectionMode)
    }
}
