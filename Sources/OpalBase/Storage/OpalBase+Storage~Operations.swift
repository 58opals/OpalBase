// OpalBase+Storage~Operations.swift

import Foundation

extension _OpalBase.Storage {
    @MainActor
    public func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try await storeValue(encodedSnapshot, for: .walletSnapshot)
    }
    
    @MainActor
    public func loadWalletSnapshot() async throws -> OpalBase.Wallet.Snapshot? {
        guard let data = try await loadValue(for: .walletSnapshot) else { return nil }
        return try decodeSnapshot(OpalBase.Wallet.Snapshot.self, from: data)
    }
    
    @MainActor
    public func saveAccountSnapshot(_ snapshot: OpalBase.Account.SnapshotModel,
                                    accountIdentifier: Data) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try await storeValue(encodedSnapshot, for: .accountSnapshot(accountIdentifier))
    }
    
    @MainActor
    public func loadAccountSnapshot(accountIdentifier: Data) async throws -> OpalBase.Account.SnapshotModel? {
        guard let data = try await loadValue(for: .accountSnapshot(accountIdentifier)) else { return nil }
        return try decodeSnapshot(OpalBase.Account.SnapshotModel.self, from: data)
    }
    
    @MainActor
    public func saveAddressBookSnapshot(_ snapshot: OpalBase.Address.Book.SnapshotModel,
                                        accountIdentifier: Data) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try await storeValue(encodedSnapshot, for: .addressBookSnapshot(accountIdentifier))
    }
    
    @MainActor
    public func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> OpalBase.Address.Book.SnapshotModel? {
        guard let data = try await loadValue(for: .addressBookSnapshot(accountIdentifier)) else { return nil }
        return try decodeSnapshot(OpalBase.Address.Book.SnapshotModel.self, from: data)
    }
    
    public func saveMnemonic(_ mnemonic: OpalBase.Storage.Mnemonic, fallbackToPlaintext: Bool = false) async throws -> SecurityModel.ProtectionMode {
        let payload = OpalBase.Storage.Mnemonic.PayloadModel(words: mnemonic.words, passphrase: mnemonic.passphrase)
        let plaintext: Data
        do {
            plaintext = try encoder.encode(payload)
        } catch {
            throw Error.encodingFailure(error)
        }
        
        let storedCiphertext: OpalBase.Storage.SecurityModel.Ciphertext
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
    
    public func loadMnemonicState() async throws -> (mnemonic: OpalBase.Storage.Mnemonic, protectionMode: SecurityModel.ProtectionMode)? {
        guard let storedCiphertext = try await loadValue(for: .mnemonicCiphertext) else { return nil }
        
        let ciphertext: OpalBase.Storage.SecurityModel.Ciphertext
        do {
            ciphertext = try decoder.decode(OpalBase.Storage.SecurityModel.Ciphertext.self, from: storedCiphertext)
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
        
        let payload: OpalBase.Storage.Mnemonic.PayloadModel
        do {
            payload = try decoder.decode(OpalBase.Storage.Mnemonic.PayloadModel.self, from: decryptedData)
        } catch {
            throw Error.decodingFailure(error)
        }
        let mnemonic = OpalBase.Storage.Mnemonic(words: payload.words, passphrase: payload.passphrase)
        return (mnemonic: mnemonic, protectionMode: ciphertext.mode)
    }
    
    public func loadMnemonic() async throws -> OpalBase.Storage.Mnemonic? {
        guard let state = try await loadMnemonicState() else { return nil }
        return state.mnemonic
    }
    
    public func persistState(for wallet: OpalBase.Wallet) async throws -> SecurityModel.ProtectionMode {
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

private extension _OpalBase.Storage {
    func checkCiphertextErrorRecoverability(_ error: Swift.Error) -> Bool {
        if security.checkSecureEnclaveErrorRecoverability(error) {
            return true
        }
        guard let securityError = error as? OpalBase.Storage.SecurityModel.Error else { return false }
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
