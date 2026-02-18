// Storage~Operations.swift

import Foundation

extension Storage {
    @MainActor
    public func saveWalletSnapshot(_ snapshot: Wallet.Snapshot) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try await storeValue(encodedSnapshot, for: .walletSnapshot)
    }
    
    @MainActor
    public func loadWalletSnapshot() async throws -> Wallet.Snapshot? {
        guard let data = try await loadValue(for: .walletSnapshot) else { return nil }
        return try decodeSnapshot(Wallet.Snapshot.self, from: data)
    }
    
    @MainActor
    public func saveAccountSnapshot(_ snapshot: Account.Snapshot,
                                    accountIdentifier: Data) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try await storeValue(encodedSnapshot, for: .accountSnapshot(accountIdentifier))
    }
    
    @MainActor
    public func loadAccountSnapshot(accountIdentifier: Data) async throws -> Account.Snapshot? {
        guard let data = try await loadValue(for: .accountSnapshot(accountIdentifier)) else { return nil }
        return try decodeSnapshot(Account.Snapshot.self, from: data)
    }
    
    @MainActor
    public func saveAddressBookSnapshot(_ snapshot: Address.Book.Snapshot,
                                        accountIdentifier: Data) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try await storeValue(encodedSnapshot, for: .addressBookSnapshot(accountIdentifier))
    }
    
    @MainActor
    public func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> Address.Book.Snapshot? {
        guard let data = try await loadValue(for: .addressBookSnapshot(accountIdentifier)) else { return nil }
        return try decodeSnapshot(Address.Book.Snapshot.self, from: data)
    }
    
    public func saveMnemonic(_ mnemonic: Mnemonic, fallbackToPlaintext: Bool = false) async throws -> Security.ProtectionMode {
        let payload = Mnemonic.Payload(words: mnemonic.words, passphrase: mnemonic.passphrase)
        let plaintext: Data
        do {
            plaintext = try encoder.encode(payload)
        } catch {
            throw Error.encodingFailure(error)
        }
        
        let storedCiphertext: Storage.Security.Ciphertext
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
    
    public func loadMnemonicState() async throws -> (mnemonic: Mnemonic, protectionMode: Security.ProtectionMode)? {
        guard let storedCiphertext = try await loadValue(for: .mnemonicCiphertext) else { return nil }
        
        let ciphertext: Storage.Security.Ciphertext
        do {
            ciphertext = try decoder.decode(Storage.Security.Ciphertext.self, from: storedCiphertext)
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
        
        let payload: Mnemonic.Payload
        do {
            payload = try decoder.decode(Mnemonic.Payload.self, from: decryptedData)
        } catch {
            throw Error.decodingFailure(error)
        }
        let mnemonic = Mnemonic(words: payload.words, passphrase: payload.passphrase)
        return (mnemonic: mnemonic, protectionMode: ciphertext.mode)
    }
    
    public func loadMnemonic() async throws -> Mnemonic? {
        guard let state = try await loadMnemonicState() else { return nil }
        return state.mnemonic
    }
    
    public func persistState(for wallet: Wallet) async throws -> Security.ProtectionMode {
        let session = PersistenceSession(storage: self)
        return try await session.save(wallet: wallet, fallbackToPlaintext: true)
    }
    
    public func delete(key: String) async throws {
        try await removeValue(for: .custom(key))
    }
    
    public func wipeAll() async throws {
        try await removeAllEntries()
    }
}

private extension Storage {
    func checkCiphertextErrorRecoverability(_ error: Swift.Error) -> Bool {
        if security.checkSecureEnclaveErrorRecoverability(error) {
            return true
        }
        guard let securityError = error as? Storage.Security.Error else { return false }
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
