// OpalBase+Storage~Operations.swift

import Foundation

extension _OpalBase.Storage {
    @MainActor
    public func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot) async throws {
        try await saveWalletSnapshot(snapshot, key: .walletSnapshot)
    }

    @MainActor
    public func loadWalletSnapshot() async throws -> OpalBase.Wallet.Snapshot? {
        try await loadWalletSnapshot(key: .walletSnapshot)
    }

    @MainActor
    public func saveAccountSnapshot(_ snapshot: OpalBase.Account.Snapshot,
                                    accountIdentifier: Data) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try await storeValue(encodedSnapshot, for: .accountSnapshot(accountIdentifier))
    }

    @MainActor
    public func loadAccountSnapshot(accountIdentifier: Data) async throws -> OpalBase.Account.Snapshot? {
        guard let data = try await loadValue(for: .accountSnapshot(accountIdentifier)) else { return nil }
        return try decodeSnapshot(OpalBase.Account.Snapshot.self, from: data)
    }

    @MainActor
    public func saveAddressBookSnapshot(_ snapshot: OpalBase.Address.Book.Snapshot,
                                        accountIdentifier: Data) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try await storeValue(encodedSnapshot, for: .addressBookSnapshot(accountIdentifier))
    }

    @MainActor
    public func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> OpalBase.Address.Book.Snapshot? {
        guard let data = try await loadValue(for: .addressBookSnapshot(accountIdentifier)) else { return nil }
        return try decodeSnapshot(OpalBase.Address.Book.Snapshot.self, from: data)
    }

    public func saveMnemonic(_ mnemonic: OpalBase.Storage.StoredMnemonic, fallbackToPlaintext: Bool = false) async throws -> Security.ProtectionMode {
        try await saveMnemonic(
            mnemonic,
            policy: fallbackToPlaintext ? .legacyFallbackToPlaintext : .acceptProviderOutput
        )
    }

    public func saveMnemonic(
        _ mnemonic: OpalBase.Storage.StoredMnemonic,
        policy: Security.PersistencePolicy
    ) async throws -> Security.ProtectionMode {
        try await saveMnemonic(
            mnemonic,
            key: .mnemonicCiphertext,
            policy: policy
        )
    }

    public func loadMnemonicState() async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: Security.ProtectionMode)? {
        try await loadMnemonicState(key: .mnemonicCiphertext)
    }

    public func deleteMnemonic() async throws {
        try await removeValue(for: .mnemonicCiphertext)
    }

    public func loadMnemonic() async throws -> OpalBase.Storage.StoredMnemonic? {
        guard let state = try await loadMnemonicState() else { return nil }
        return state.mnemonic
    }

    public func persistState(for wallet: OpalBase.Wallet) async throws -> Security.ProtectionMode {
        try await persistState(for: wallet, policy: .legacyFallbackToPlaintext)
    }

    public func persistState(
        for wallet: OpalBase.Wallet,
        policy: Security.PersistencePolicy
    ) async throws -> Security.ProtectionMode {
        let session = PersistenceSession(storage: self)
        return try await session.save(wallet: wallet, policy: policy)
    }

    public func delete(key: String) async throws {
        try await removeValue(for: .custom(key))
    }

    public func wipeAll() async throws {
        try await removeAllEntries()
        try security.resetProtectedMaterial()
    }
}

extension _OpalBase.Storage {
    @MainActor
    func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot, generation: String) async throws {
        try await saveWalletSnapshot(snapshot, key: .walletSnapshotGeneration(generation))
    }

    @MainActor
    func loadWalletSnapshot(generation: String) async throws -> OpalBase.Wallet.Snapshot? {
        try await loadWalletSnapshot(key: .walletSnapshotGeneration(generation))
    }

    func deleteWalletSnapshot(generation: String) async throws {
        try await removeValue(for: .walletSnapshotGeneration(generation))
    }

    func saveCommittedWalletSnapshotGeneration(_ generation: String) async throws {
        try await storeValue(Data(generation.utf8), for: .walletSnapshotCommittedGeneration)
    }

    func loadCommittedWalletSnapshotGeneration() async throws -> String? {
        guard let data = try await loadValue(for: .walletSnapshotCommittedGeneration) else {
            return nil
        }

        guard let generation = String(data: data, encoding: .utf8) else {
            throw Error.decodingFailure(
                NSError(
                    domain: NSCocoaErrorDomain,
                    code: CocoaError.Code.coderInvalidValue.rawValue,
                    userInfo: [NSDebugDescriptionErrorKey: "Committed wallet snapshot generation is not valid UTF-8."]
                )
            )
        }

        return generation
    }

    func deleteCommittedWalletSnapshotGeneration() async throws {
        try await removeValue(for: .walletSnapshotCommittedGeneration)
    }

    func saveMnemonic(
        _ mnemonic: OpalBase.Storage.StoredMnemonic,
        generation: String,
        fallbackToPlaintext: Bool = false
    ) async throws -> Security.ProtectionMode {
        try await saveMnemonic(
            mnemonic,
            generation: generation,
            policy: fallbackToPlaintext ? .legacyFallbackToPlaintext : .acceptProviderOutput
        )
    }

    func saveMnemonic(
        _ mnemonic: OpalBase.Storage.StoredMnemonic,
        generation: String,
        policy: Security.PersistencePolicy
    ) async throws -> Security.ProtectionMode {
        try await saveMnemonic(
            mnemonic,
            key: .mnemonicCiphertextGeneration(generation),
            policy: policy
        )
    }

    func loadMnemonicState(
        generation: String
    ) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: Security.ProtectionMode)? {
        try await loadMnemonicState(key: .mnemonicCiphertextGeneration(generation))
    }

    func deleteMnemonic(generation: String) async throws {
        try await removeValue(for: .mnemonicCiphertextGeneration(generation))
    }
}

private extension _OpalBase.Storage {
    @MainActor
    func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot, key: OpalBase.Storage.Key) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try await storeValue(encodedSnapshot, for: key)
    }

    @MainActor
    func loadWalletSnapshot(key: OpalBase.Storage.Key) async throws -> OpalBase.Wallet.Snapshot? {
        guard let data = try await loadValue(for: key) else { return nil }
        return try decodeSnapshot(OpalBase.Wallet.Snapshot.self, from: data)
    }

    func saveMnemonic(
        _ mnemonic: OpalBase.Storage.StoredMnemonic,
        key: OpalBase.Storage.Key,
        fallbackToPlaintext: Bool = false
    ) async throws -> Security.ProtectionMode {
        try await saveMnemonic(
            mnemonic,
            key: key,
            policy: fallbackToPlaintext ? .legacyFallbackToPlaintext : .acceptProviderOutput
        )
    }

    func saveMnemonic(
        _ mnemonic: OpalBase.Storage.StoredMnemonic,
        key: OpalBase.Storage.Key,
        policy: Security.PersistencePolicy
    ) async throws -> Security.ProtectionMode {
        let payload = OpalBase.Storage.StoredMnemonic.Payload(words: mnemonic.words, passphrase: mnemonic.passphrase)
        let plaintext: Data
        do {
            plaintext = try encoder.encode(payload)
        } catch {
            throw Error.encodingFailure(error)
        }
        
        let storedCiphertext: OpalBase.Storage.Security.Ciphertext
        do {
            let ciphertext = try security.encrypt(plaintext)
            switch policy {
            case .acceptProviderOutput:
                storedCiphertext = ciphertext
            case .legacyFallbackToPlaintext:
                storedCiphertext = ciphertext.mode == .secureEnclave
                    ? ciphertext
                    : .init(mode: .plaintext, payload: plaintext)
            case .requireSecureEnclave:
                guard ciphertext.mode == .secureEnclave else {
                    throw Security.Error.insufficientProtection(required: .secureEnclave, actual: ciphertext.mode)
                }
                storedCiphertext = ciphertext
            }
        } catch {
            if policy == .legacyFallbackToPlaintext && checkCiphertextErrorRecoverability(error) {
                storedCiphertext = .init(mode: .plaintext, payload: plaintext)
            } else {
                throw Error.secureStoreFailure(error)
            }
        }
        
        let encodedCiphertext: Data
        do {
            encodedCiphertext = try encoder.encode(storedCiphertext)
        } catch {
            throw Error.encodingFailure(error)
        }
        
        try await storeValue(encodedCiphertext, for: key)
        return storedCiphertext.mode
    }
    
    func loadMnemonicState(
        key: OpalBase.Storage.Key
    ) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: Security.ProtectionMode)? {
        guard let storedCiphertext = try await loadValue(for: key) else { return nil }
        
        let ciphertext: OpalBase.Storage.Security.Ciphertext
        do {
            ciphertext = try decoder.decode(OpalBase.Storage.Security.Ciphertext.self, from: storedCiphertext)
        } catch {
            ciphertext = .init(mode: .secureEnclave, payload: storedCiphertext)
        }
        
        let decryptedData: Data
        switch ciphertext.mode {
        case .plaintext:
            decryptedData = ciphertext.payload
        default:
            do {
                decryptedData = try security.decrypt(ciphertext)
            } catch {
                throw Error.secureStoreFailure(error)
            }
        }
        
        let payload: OpalBase.Storage.StoredMnemonic.Payload
        do {
            payload = try decoder.decode(OpalBase.Storage.StoredMnemonic.Payload.self, from: decryptedData)
        } catch {
            throw Error.decodingFailure(error)
        }
        let mnemonic = OpalBase.Storage.StoredMnemonic(words: payload.words, passphrase: payload.passphrase)
        return (mnemonic: mnemonic, protectionMode: ciphertext.mode)
    }
}

private extension _OpalBase.Storage {
    func checkCiphertextErrorRecoverability(_ error: Swift.Error) -> Bool {
        if security.checkSecureEnclaveErrorRecoverability(error) {
            return true
        }
        guard let securityError = error as? OpalBase.Storage.Security.Error else { return false }
        switch securityError {
        case .protectionUnavailable:
            return true
        case .insufficientProtection:
            return true
        case .encryptionFailure(let underlying):
            return security.checkSecureEnclaveErrorRecoverability(underlying)
        case .decryptionFailure:
            return false
        }
    }
}
