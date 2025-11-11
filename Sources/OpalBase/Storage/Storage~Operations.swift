// Storage~Operations.swift

import Foundation
import SwiftData

extension Storage {
    public func saveWalletSnapshot(_ snapshot: Wallet.Snapshot) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try storeValue(encodedSnapshot, for: .walletSnapshot)
    }
    
    public func loadWalletSnapshot() async throws -> Wallet.Snapshot? {
        guard let data = try loadValue(for: .walletSnapshot) else { return nil }
        return try decodeSnapshot(Wallet.Snapshot.self, from: data)
    }
    
    public func saveAccountSnapshot(_ snapshot: Account.Snapshot,
                                    accountIdentifier: Data) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try storeValue(encodedSnapshot, for: .accountSnapshot(accountIdentifier))
    }
    
    public func loadAccountSnapshot(accountIdentifier: Data) async throws -> Account.Snapshot? {
        guard let data = try loadValue(for: .accountSnapshot(accountIdentifier)) else { return nil }
        return try decodeSnapshot(Account.Snapshot.self, from: data)
    }
    
    public func saveAddressBookSnapshot(_ snapshot: Address.Book.Snapshot,
                                        accountIdentifier: Data) async throws {
        let encodedSnapshot = try encodeSnapshot(snapshot)
        try storeValue(encodedSnapshot, for: .addressBookSnapshot(accountIdentifier))
    }
    
    public func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> Address.Book.Snapshot? {
        guard let data = try loadValue(for: .addressBookSnapshot(accountIdentifier)) else { return nil }
        return try decodeSnapshot(Address.Book.Snapshot.self, from: data)
    }
    
    public func saveMnemonic(_ mnemonic: Mnemonic) async throws {
        let payload = Mnemonic.Payload(words: mnemonic.words, passphrase: mnemonic.passphrase)
        let plaintext: Data
        do {
            plaintext = try encoder.encode(payload)
        } catch {
            throw Error.encodingFailure(error)
        }
        
        let ciphertext: Data
        do {
            ciphertext = try security.encrypt(plaintext)
        } catch {
            throw Error.secureStoreFailure(error)
        }
        
        try storeValue(ciphertext, for: .mnemonicCiphertext)
    }
    
    public func loadMnemonic() async throws -> Mnemonic? {
        guard let ciphertext = try loadValue(for: .mnemonicCiphertext) else { return nil }
        let decryptedData: Data
        do {
            decryptedData = try security.decrypt(ciphertext)
        } catch {
            throw Error.secureStoreFailure(error)
        }
        
        let payload: Mnemonic.Payload
        do {
            payload = try decoder.decode(Mnemonic.Payload.self, from: decryptedData)
        } catch {
            throw Error.decodingFailure(error)
        }
        return Mnemonic(words: payload.words, passphrase: payload.passphrase)
    }
    
    public func delete(key: String) async throws {
        try removeValue(for: .custom(key))
    }
    
    public func wipeAll() async throws {
        try removeAllEntries()
    }
}
