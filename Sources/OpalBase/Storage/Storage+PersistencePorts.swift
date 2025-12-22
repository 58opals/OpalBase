// Storage+PersistencePorts.swift

import Foundation

extension Storage.Ports {
    init(operations: Storage.PersistenceSession.Operations) {
        self.init(snapshotPersistence: SnapshotOperationsPort(operations: operations),
                  secretAccess: SecureSecretOperationsPort(operations: operations))
    }
}

private struct SnapshotOperationsPort: SnapshotPersistencePort {
    let operations: Storage.PersistenceSession.Operations
    
    func saveWalletSnapshot(_ snapshot: Wallet.Snapshot) async throws {
        try await operations.saveWalletSnapshot(snapshot)
    }
    
    func loadWalletSnapshot() async throws -> Wallet.Snapshot? {
        try await operations.loadWalletSnapshot()
    }
    
    func saveAccountSnapshot(_ snapshot: Account.Snapshot, accountIdentifier: Data) async throws {
        try await operations.saveAccountSnapshot(snapshot, accountIdentifier)
    }
    
    func loadAccountSnapshot(accountIdentifier: Data) async throws -> Account.Snapshot? {
        try await operations.loadAccountSnapshot(accountIdentifier)
    }
    
    func saveAddressBookSnapshot(_ snapshot: Address.Book.Snapshot, accountIdentifier: Data) async throws {
        try await operations.saveAddressBookSnapshot(snapshot, accountIdentifier)
    }
    
    func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> Address.Book.Snapshot? {
        try await operations.loadAddressBookSnapshot(accountIdentifier)
    }
    
    func wipeAll() async throws {
        try await operations.wipeAll()
    }
}

private struct SecureSecretOperationsPort: SecureSecretAccessPort {
    let operations: Storage.PersistenceSession.Operations
    
    func saveMnemonic(_ mnemonic: Storage.Mnemonic,
                      fallbackToPlaintext: Bool) async throws -> Storage.Security.ProtectionMode {
        try await operations.saveMnemonic(mnemonic, fallbackToPlaintext)
    }
    
    func loadMnemonicState() async throws -> (mnemonic: Storage.Mnemonic, protectionMode: Storage.Security.ProtectionMode)? {
        try await operations.loadMnemonicState()
    }
}
