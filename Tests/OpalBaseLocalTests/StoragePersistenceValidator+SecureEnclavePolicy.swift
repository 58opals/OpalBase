// StoragePersistenceValidator+SecureEnclavePolicy.swift

import Foundation
import Security
import Testing
@testable import OpalBase

extension StoragePersistenceValidator {
    @Test("ciphertexts normalize sliced payload data")
    func ciphertextsNormalizeSlicedPayloadData() {
        let payload = Data("secret-payload".utf8)
        let paddedPayload = Data([0x00]) + payload
        let slicedPayload = paddedPayload[paddedPayload.index(after: paddedPayload.startIndex)...]

        let ciphertext = OpalBase.Storage.Security.Ciphertext(
            mode: .software,
            payload: slicedPayload
        )

        #expect(slicedPayload.startIndex != 0)
        #expect(ciphertext.payload == payload)
        #expect(ciphertext.payload.startIndex == 0)
    }

    @Test("Secure Enclave envelopes normalize sliced byte fields")
    func secureEnclaveEnvelopesNormalizeSlicedByteFields() {
        let salt = Data(repeating: 0x01, count: 32)
        let publicKey = Data(repeating: 0x02, count: 65)
        let ciphertext = Data(repeating: 0x03, count: 48)
        let slicedSalt = Self.makeSlicedData(from: salt)
        let slicedPublicKey = Self.makeSlicedData(from: publicKey)
        let slicedCiphertext = Self.makeSlicedData(from: ciphertext)

        let envelope = SecureEnclaveEnvelope(
            version: 1,
            salt: slicedSalt,
            ephemeralPublicKeyRepresentation: slicedPublicKey,
            combinedCiphertext: slicedCiphertext
        )

        #expect(slicedSalt.startIndex != 0)
        #expect(slicedPublicKey.startIndex != 0)
        #expect(slicedCiphertext.startIndex != 0)
        #expect(envelope.salt == salt)
        #expect(envelope.salt.startIndex == 0)
        #expect(envelope.ephemeralPublicKeyRepresentation == publicKey)
        #expect(envelope.ephemeralPublicKeyRepresentation.startIndex == 0)
        #expect(envelope.combinedCiphertext == ciphertext)
        #expect(envelope.combinedCiphertext.startIndex == 0)
    }

    @Test("acceptProviderOutput preserves non-enclave protection modes")
    func acceptProviderOutputPreservesSoftwareProtectionMode() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let security = OpalBase.Storage.Security(
            encrypt: { value in
                .init(mode: .software, payload: value)
            },
            decrypt: { ciphertext in
                ciphertext.payload
            }
        )
        let storage = try OpalBase.Storage(valueClient: valueClient, security: security)

        let protectionMode = try await storage.saveMnemonic(
            Self.makeStoredMnemonic(passphrase: "software-mode"),
            policy: .acceptProviderOutput
        )

        #expect(protectionMode == .software)

        let restored = try #require(try await storage.loadMnemonicState())
        #expect(restored.mnemonic.passphrase == "software-mode")
        #expect(restored.protectionMode == .software)
    }

    @Test("requireSecureEnclave fails closed when only plaintext protection is available")
    func requireSecureEnclaveFailsClosedForPlaintextSecurity() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let storage = try OpalBase.Storage(valueClient: valueClient, security: .makePlaintextOnly())

        do {
            _ = try await storage.saveMnemonic(
                Self.makeStoredMnemonic(passphrase: "fail-closed"),
                policy: .requireSecureEnclave
            )
            Issue.record("Expected requireSecureEnclave to reject plaintext protection.")
        } catch {
            Self.expectInsufficientProtection(error)
        }

        #expect(try await storage.loadMnemonicState() == nil)
    }

    @Test("legacy plaintext fallback handles wrapped protection-unavailable errors")
    func legacyPlaintextFallbackHandlesWrappedProtectionUnavailable() async throws {
        let valueClient = OpalBase.Storage.ValueClient.makeInMemory()
        let security = OpalBase.Storage.Security(
            encrypt: { _ in
                throw OpalBase.Storage.Security.Error.protectionUnavailable
            },
            decrypt: { ciphertext in
                ciphertext.payload
            }
        )
        let storage = try OpalBase.Storage(valueClient: valueClient, security: security)

        let protectionMode = try await storage.saveMnemonic(
            Self.makeStoredMnemonic(passphrase: "wrapped-protection"),
            policy: .legacyFallbackToPlaintext
        )

        #expect(protectionMode == .plaintext)
        let restored = try #require(try await storage.loadMnemonicState())
        #expect(restored.mnemonic.passphrase == "wrapped-protection")
        #expect(restored.protectionMode == .plaintext)
    }

    @Test("persistState(policy: .requireSecureEnclave) leaves no committed artifacts when protection fails")
    func persistStateRequireSecureEnclaveRollsBackStagedArtifacts() async throws {
        let storage = try OpalBase.Storage(valueClient: .makeInMemory(), security: .makePlaintextOnly())
        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "rollback")

        do {
            _ = try await storage.persistState(for: wallet, policy: .requireSecureEnclave)
            Issue.record("Expected strict Secure Enclave persistence to fail with plaintext-only security.")
        } catch {
            Self.expectInsufficientProtection(error)
        }

        #expect(try await storage.loadCommittedWalletSnapshotGeneration() == nil)
        #expect(try await storage.loadMnemonicState() == nil)
        #expect(try await storage.loadWalletSnapshot() == nil)
    }

    @Test("legacy mnemonic persistence rolls back weaker writes for strict Secure Enclave policy")
    func legacyMnemonicPersistenceRollsBackWeakerWritesForStrictSecureEnclavePolicy() async throws {
        let state = LegacyStoredMnemonicPersistenceState()
        let persistence = OpalBase.Storage.StoredMnemonicPersistence(
            saveMnemonic: { mnemonic, generation, _ in
                await state.saveMnemonic(
                    mnemonic,
                    generation: generation,
                    protectionMode: .software
                )
            },
            loadMnemonicState: { generation in
                await state.loadMnemonicState(generation: generation)
            },
            deleteMnemonic: { generation in
                await state.deleteMnemonic(generation: generation)
            }
        )
        let generation = "strict-generation"

        do {
            _ = try await persistence.saveMnemonic(
                Self.makeStoredMnemonic(passphrase: "legacy-strict"),
                generation: generation,
                policy: .requireSecureEnclave
            )
            Issue.record("Expected strict Secure Enclave policy to reject software protection.")
        } catch OpalBase.Storage.Security.Error.insufficientProtection(
            required: .secureEnclave,
            actual: .software
        ) {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(try await persistence.loadMnemonicState(generation: generation) == nil)
    }

    @Test("policy-aware mnemonic persistence rolls back weaker writes for strict Secure Enclave policy")
    func policyAwareMnemonicPersistenceRollsBackWeakerWritesForStrictSecureEnclavePolicy() async throws {
        let state = LegacyStoredMnemonicPersistenceState()
        let persistence = OpalBase.Storage.StoredMnemonicPersistence(
            saveMnemonicWithPolicy: { mnemonic, generation, _ in
                await state.saveMnemonic(
                    mnemonic,
                    generation: generation,
                    protectionMode: .software
                )
            },
            loadMnemonicState: { generation in
                await state.loadMnemonicState(generation: generation)
            },
            deleteMnemonic: { generation in
                await state.deleteMnemonic(generation: generation)
            }
        )
        let generation = "strict-policy-aware-generation"

        do {
            _ = try await persistence.saveMnemonic(
                Self.makeStoredMnemonic(passphrase: "policy-aware-strict"),
                generation: generation,
                policy: .requireSecureEnclave
            )
            Issue.record("Expected strict Secure Enclave policy to reject software protection.")
        } catch OpalBase.Storage.Security.Error.insufficientProtection(
            required: .secureEnclave,
            actual: .software
        ) {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(try await persistence.loadMnemonicState(generation: generation) == nil)
    }

    @Test("Secure Enclave factory encrypts with secureEnclave mode when hardware is available")
    func secureEnclaveFactoryEncryptsOrFailsWithProtectionUnavailable() async throws {
        let configuration = OpalBase.Storage.Security.SecureEnclaveConfiguration(
            applicationTag: "OpalBase.Tests.SecureEnclave.\(UUID().uuidString)"
        )
        let applicationTag = Data(configuration.applicationTag.utf8)

        do {
            let security = try OpalBase.Storage.Security.makeSecureEnclaveBacked(configuration: configuration)
            #expect(try SecureEnclaveAdapter.findPrivateKey(applicationTag: applicationTag) != nil)
            let storage = try OpalBase.Storage(valueClient: .makeInMemory(), security: security)
            let protectionMode = try await storage.saveMnemonic(
                Self.makeStoredMnemonic(passphrase: "secure-enclave"),
                policy: .requireSecureEnclave
            )
            #expect(protectionMode == .secureEnclave)
            try await storage.wipeAll()
        } catch {
            Self.expectProtectionUnavailable(error)
        }
    }

    @Test("Secure Enclave key lookup requests a SecKey reference instead of a persistent reference")
    func secureEnclaveKeyLookupUsesKeyReference() {
        let query = SecureEnclaveAdapter.keyQuery(
            applicationTag: Data("OpalBase.Tests.SecureEnclave.Query".utf8),
            returnReference: true
        )

        #expect(query[kSecReturnRef as String] as? Bool == true)
        #expect(query[kSecReturnPersistentRef as String] == nil)
    }

    @Test("Security.framework key agreement helpers round trip public-key envelopes")
    func securityKeyAgreementHelpersRoundTripEnvelopeKeys() throws {
        let recipientPrivateKey = try SecureEnclaveAdapter.createEphemeralPrivateKey()
        let recipientPublicKey = try SecureEnclaveAdapter.copyPublicKey(for: recipientPrivateKey)
        let ephemeralPrivateKey = try SecureEnclaveAdapter.createEphemeralPrivateKey()
        let ephemeralPublicKey = try SecureEnclaveAdapter.copyPublicKey(for: ephemeralPrivateKey)

        let encryptSharedSecret = try SecureEnclaveAdapter.copyKeyAgreementSharedSecret(
            privateKey: ephemeralPrivateKey,
            publicKey: recipientPublicKey
        )
        let ephemeralPublicKeyRepresentation = try SecureEnclaveAdapter.externalRepresentation(
            of: ephemeralPublicKey,
            message: "Failed to export the test ephemeral public key."
        )
        let restoredEphemeralPublicKey = try SecureEnclaveAdapter.makePublicKey(
            x963Representation: ephemeralPublicKeyRepresentation
        )
        let decryptSharedSecret = try SecureEnclaveAdapter.copyKeyAgreementSharedSecret(
            privateKey: recipientPrivateKey,
            publicKey: restoredEphemeralPublicKey
        )

        #expect(encryptSharedSecret == decryptSharedSecret)
    }

    @Test(
        "Secure Enclave setup classifies corrupt key references as recoverable",
        arguments: [errSecDecode, errSecParam]
    )
    func secureEnclaveSetupClassifiesCorruptKeyReferencesAsRecoverable(status: OSStatus) {
        let error = NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSDebugDescriptionErrorKey: "corrupted objectID detected"]
        )

        #expect(SecureEnclaveAdapter.isRecoverable(error))
    }
}

private extension StoragePersistenceValidator {
    static func makeStoredMnemonic(
        passphrase: String = ""
    ) -> OpalBase.Storage.StoredMnemonic {
        OpalBase.Storage.StoredMnemonic(
            words: AccountTestFixtures.mnemonicWords,
            passphrase: passphrase
        )
    }

    static func expectInsufficientProtection(_ error: Swift.Error) {
        guard case OpalBase.Storage.Error.secureStoreFailure(let underlying) = error else {
            Issue.record("Expected secureStoreFailure, got \(error).")
            return
        }

        if isInsufficientProtectionError(underlying) {
            return
        }

        Issue.record("Expected insufficient protection failure, got \(error).")
    }

    static func expectProtectionUnavailable(_ error: Swift.Error) {
        if isProtectionUnavailableError(error) {
            return
        }

        guard case OpalBase.Storage.Error.secureStoreFailure(let underlying) = error else {
            Issue.record("Expected protectionUnavailable, got \(error).")
            return
        }

        if isProtectionUnavailableError(underlying) {
            return
        }

        Issue.record("Expected protectionUnavailable, got \(error).")
    }

    static func isInsufficientProtectionError(_ error: Swift.Error) -> Bool {
        guard let securityError = error as? OpalBase.Storage.Security.Error else { return false }

        switch securityError {
        case .insufficientProtection(required: .secureEnclave, actual: .plaintext):
            return true
        case .encryptionFailure(let nested), .decryptionFailure(let nested):
            return isInsufficientProtectionError(nested)
        default:
            return false
        }
    }

    static func isProtectionUnavailableError(_ error: Swift.Error) -> Bool {
        switch error {
        case OpalBase.Storage.Security.Error.protectionUnavailable:
            return true
        case OpalBase.Storage.Security.Error.encryptionFailure(let nested),
            OpalBase.Storage.Security.Error.decryptionFailure(let nested):
            return isProtectionUnavailableError(nested)
        default:
            break
        }

        let nsError = error as NSError
        return nsError.domain == NSOSStatusErrorDomain
            && [
                Int(errSecNotAvailable),
                Int(errSecMissingEntitlement),
                Int(errSecInteractionNotAllowed)
            ].contains(nsError.code)
    }

    private static func makeSlicedData(from data: Data) -> Data {
        let paddedData = Data([0x00]) + data
        return paddedData[paddedData.index(after: paddedData.startIndex)...]
    }
}
