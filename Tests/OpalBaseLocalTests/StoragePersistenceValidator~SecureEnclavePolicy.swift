// StoragePersistenceValidator~SecureEnclavePolicy.swift

import Foundation
import Security
import Testing
@testable import OpalBase

extension StoragePersistenceValidator {
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

        let restored = try await storage.loadMnemonicState()
        #expect(restored?.mnemonic.passphrase == "software-mode")
        #expect(restored?.protectionMode == .software)
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

    @Test("legacy mnemonic store rolls back weaker writes for strict Secure Enclave policy")
    func legacyMnemonicStoreRollsBackWeakerWritesForStrictSecureEnclavePolicy() async throws {
        let state = LegacyStoredMnemonicStoreState()
        let store = OpalBase.Storage.StoredMnemonicStore(
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
            _ = try await store.saveMnemonic(
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

        #expect(try await store.loadMnemonicState(generation: generation) == nil)
    }

    @Test("Secure Enclave factory encrypts with secureEnclave mode when hardware is available")
    func secureEnclaveFactoryEncryptsOrFailsWithProtectionUnavailable() async throws {
        let configuration = OpalBase.Storage.Security.SecureEnclaveConfiguration(
            applicationTag: "OpalBase.Tests.SecureEnclave.\(UUID().uuidString)"
        )

        do {
            let security = try OpalBase.Storage.Security.makeSecureEnclaveBacked(configuration: configuration)
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
}

private actor LegacyStoredMnemonicStoreState {
    private var states: [
        String: (
            mnemonic: OpalBase.Storage.StoredMnemonic,
            protectionMode: OpalBase.Storage.Security.ProtectionMode
        )
    ] = [:]

    func saveMnemonic(
        _ mnemonic: OpalBase.Storage.StoredMnemonic,
        generation: String,
        protectionMode: OpalBase.Storage.Security.ProtectionMode
    ) -> OpalBase.Storage.Security.ProtectionMode {
        states[generation] = (mnemonic, protectionMode)
        return protectionMode
    }

    func loadMnemonicState(
        generation: String
    ) -> (
        mnemonic: OpalBase.Storage.StoredMnemonic,
        protectionMode: OpalBase.Storage.Security.ProtectionMode
    )? {
        states[generation]
    }

    func deleteMnemonic(generation: String) {
        states[generation] = nil
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
        if let securityError = error as? OpalBase.Storage.Security.Error {
            switch securityError {
            case .protectionUnavailable:
                return true
            case .encryptionFailure(let nested), .decryptionFailure(let nested):
                return isProtectionUnavailableError(nested)
            case .insufficientProtection:
                return false
            }
        }

        let nsError = error as NSError
        return nsError.domain == NSOSStatusErrorDomain
            && [
                Int(errSecNotAvailable),
                Int(errSecMissingEntitlement),
                Int(errSecInteractionNotAllowed)
            ].contains(nsError.code)
    }
}
