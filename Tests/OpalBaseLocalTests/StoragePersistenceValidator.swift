// StoragePersistenceValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Storage persistence and wallet workflows", .tags(.unit, .wallet))
struct StoragePersistenceValidator {
    @Test("in-memory value client normalizes sliced payloads")
    func inMemoryValueClientNormalizesSlicedPayloads() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let payload = Data([0x01, 0x02, 0x03])
        let paddedPayload = Data([0x00]) + payload
        let slicedPayload = paddedPayload[paddedPayload.index(after: paddedPayload.startIndex)...]

        try await valueClient.valueWriter(slicedPayload, .custom("slice"))
        let restoredPayload = try #require(try await valueClient.valueReader(.custom("slice")))

        #expect(slicedPayload.startIndex != payload.startIndex)
        #expect(restoredPayload == payload)
        #expect(restoredPayload.startIndex == payload.startIndex)
    }

    @Test("custom value client normalizes sliced closure payloads")
    func customValueClientNormalizesSlicedClosurePayloads() async throws {
        let writtenPayload = Data([0x04, 0x05, 0x06])
        let readPayload = Data([0x07, 0x08, 0x09])
        let slicedWrittenPayload = makeSlicedData(from: writtenPayload)
        let slicedReadPayload = makeSlicedData(from: readPayload)
        let probe = ValueClientProbe(readPayload: slicedReadPayload)
        let valueClient = OpalBase.Storage.ValueClient(
            valueWriter: { data, key in
                await probe.store(data, key: key)
            },
            valueReader: { key in
                await probe.load(key: key)
            },
            valueDeleter: { _ in },
            allValuesDeleter: {}
        )

        try await valueClient.valueWriter(slicedWrittenPayload, .custom("write"))
        let capturedPayload = try #require(await probe.capturedPayload())
        let restoredPayload = try #require(try await valueClient.valueReader(.custom("read")))

        #expect(slicedWrittenPayload.startIndex != writtenPayload.startIndex)
        #expect(slicedReadPayload.startIndex != readPayload.startIndex)
        #expect(capturedPayload == writtenPayload)
        #expect(capturedPayload.startIndex == writtenPayload.startIndex)
        #expect(restoredPayload == readPayload)
        #expect(restoredPayload.startIndex == readPayload.startIndex)
    }

    @Test("custom security normalizes sliced plaintext closure payloads")
    func customSecurityNormalizesSlicedPlaintextClosurePayloads() throws {
        let encryptedPayload = Data([0x0a, 0x0b, 0x0c])
        let decryptedPayload = Data([0x0d, 0x0e, 0x0f])
        let slicedEncryptedPayload = makeSlicedData(from: encryptedPayload)
        let slicedDecryptedPayload = makeSlicedData(from: decryptedPayload)
        let probe = SecurityProbe()
        let security = OpalBase.Storage.Security(
            encrypt: { value in
                probe.encryptedPayload = value
                return OpalBase.Storage.Security.Ciphertext(mode: .software, payload: value)
            },
            decrypt: { _ in
                slicedDecryptedPayload
            }
        )

        let ciphertext = try security.encrypt(slicedEncryptedPayload)
        let capturedPayload = try #require(probe.encryptedPayload)
        let restoredPayload = try security.decrypt(ciphertext)

        #expect(slicedEncryptedPayload.startIndex != encryptedPayload.startIndex)
        #expect(slicedDecryptedPayload.startIndex != decryptedPayload.startIndex)
        #expect(capturedPayload == encryptedPayload)
        #expect(capturedPayload.startIndex == encryptedPayload.startIndex)
        #expect(ciphertext.payload == encryptedPayload)
        #expect(ciphertext.payload.startIndex == encryptedPayload.startIndex)
        #expect(restoredPayload == decryptedPayload)
        #expect(restoredPayload.startIndex == decryptedPayload.startIndex)
    }

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
        #expect(OpalBase.Storage.Key.walletSnapshotGeneration("committed").rawValue == "wallet.snapshot.generation.committed")
        #expect(OpalBase.Storage.Key.walletSnapshotGeneration("committed").rawValue != OpalBase.Storage.Key.walletSnapshotCommittedGeneration.rawValue)
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
        let restored = try #require(try await restoredStorage.loadMnemonicState())

        #expect(restored.mnemonic.words == mnemonic.words)
        #expect(restored.mnemonic.passphrase == mnemonic.passphrase)
        #expect(restored.protectionMode == protectionMode)
    }

    private func makeSlicedData(from data: Data) -> Data {
        let paddedData = Data([0x00]) + data
        return paddedData[paddedData.index(after: paddedData.startIndex)...]
    }

    final class SecurityProbe: @unchecked Sendable {
        var encryptedPayload: Data?
    }

    actor ValueClientProbe {
        private var writtenPayload: Data?
        private let readPayload: Data

        init(readPayload: Data) {
            self.readPayload = readPayload
        }

        func store(_ data: Data, key _: OpalBase.Storage.Key) {
            writtenPayload = data
        }

        func load(key _: OpalBase.Storage.Key) -> Data {
            readPayload
        }

        func capturedPayload() -> Data? {
            writtenPayload
        }
    }
}
