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
            && [Int(errSecNotAvailable), Int(errSecMissingEntitlement)].contains(nsError.code)
    }
}
