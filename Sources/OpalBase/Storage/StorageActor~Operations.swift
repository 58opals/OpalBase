// StorageActor~OperationsModel.swift

import Foundation

extension StorageActor {
    @MainActor
    public func saveWalletSnapshot(_ snapshot: WalletActor.SnapshotModel) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try await storeValue(encodedSnapshot, for: .walletSnapshot)
    }
    
    @MainActor
    public func loadWalletSnapshot() async throws -> WalletActor.SnapshotModel? {
        guard let data = try await loadValue(for: .walletSnapshot) else { return nil }
        return try decodeSnapshot(WalletActor.SnapshotModel.self, from: data)
    }
    
    @MainActor
    public func saveAccountSnapshot(_ snapshot: AccountActor.SnapshotModel,
                                    accountIdentifier: Data) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try await storeValue(encodedSnapshot, for: .accountSnapshot(accountIdentifier))
    }
    
    @MainActor
    public func loadAccountSnapshot(accountIdentifier: Data) async throws -> AccountActor.SnapshotModel? {
        guard let data = try await loadValue(for: .accountSnapshot(accountIdentifier)) else { return nil }
        return try decodeSnapshot(AccountActor.SnapshotModel.self, from: data)
    }
    
    @MainActor
    public func saveAddressBookSnapshot(_ snapshot: AddressModel.BookActor.SnapshotModel,
                                        accountIdentifier: Data) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try await storeValue(encodedSnapshot, for: .addressBookSnapshot(accountIdentifier))
    }
    
    @MainActor
    public func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> AddressModel.BookActor.SnapshotModel? {
        guard let data = try await loadValue(for: .addressBookSnapshot(accountIdentifier)) else { return nil }
        return try decodeSnapshot(AddressModel.BookActor.SnapshotModel.self, from: data)
    }
    
    public func saveMnemonic(_ mnemonic: MnemonicModel, fallbackToPlaintext: Bool = false) async throws -> SecurityModel.ProtectionMode {
        let payload = MnemonicModel.PayloadModel(words: mnemonic.words, passphrase: mnemonic.passphrase)
        let plaintext: Data
        do {
            plaintext = try encoder.encode(payload)
        } catch {
            throw Error.encodingFailure(error)
        }
        
        let storedCiphertext: StorageActor.SecurityModel.Ciphertext
        do {
            let ciphertext = try security.encrypt(plaintext)
            if fallbackToPlaintext && ciphertext.mode != .secureEnclave {
                storedCiphertext = .init(mode: .plaintext, payload: plaintext)
            } else {
                storedCiphertext = ciphertext
            }
        } catch {
            if fallbackToPlaintext && checkCiphertextErrorRecoverability(error) {
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
        
        try await storeValue(encodedCiphertext, for: .mnemonicCiphertext)
        return storedCiphertext.mode
    }
    
    public func loadMnemonicState() async throws -> (mnemonic: MnemonicModel, protectionMode: SecurityModel.ProtectionMode)? {
        guard let storedCiphertext = try await loadValue(for: .mnemonicCiphertext) else { return nil }
        
        let ciphertext: StorageActor.SecurityModel.Ciphertext
        do {
            ciphertext = try decoder.decode(StorageActor.SecurityModel.Ciphertext.self, from: storedCiphertext)
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
        
        let payload: MnemonicModel.PayloadModel
        do {
            payload = try decoder.decode(MnemonicModel.PayloadModel.self, from: decryptedData)
        } catch {
            throw Error.decodingFailure(error)
        }
        let mnemonic = MnemonicModel(words: payload.words, passphrase: payload.passphrase)
        return (mnemonic: mnemonic, protectionMode: ciphertext.mode)
    }
    
    public func loadMnemonic() async throws -> MnemonicModel? {
        guard let state = try await loadMnemonicState() else { return nil }
        return state.mnemonic
    }
    
    public func persistState(for wallet: WalletActor) async throws -> SecurityModel.ProtectionMode {
        let session = PersistenceSessionModel(storage: self)
        return try await session.save(wallet: wallet, fallbackToPlaintext: true)
    }
    
    public func delete(key: String) async throws {
        try await removeValue(for: .custom(key))
    }
    
    public func wipeAll() async throws {
        try await removeAllEntries()
    }
}

private extension StorageActor {
    func checkCiphertextErrorRecoverability(_ error: Swift.Error) -> Bool {
        if security.checkSecureEnclaveErrorRecoverability(error) {
            return true
        }
        guard let securityError = error as? StorageActor.SecurityModel.Error else { return false }
        switch securityError {
        case .protectionUnavailable:
            return true
        case .encryptionFailure(let underlying):
            return security.checkSecureEnclaveErrorRecoverability(underlying)
        case .decryptionFailure:
            return false
        }
    }
}
