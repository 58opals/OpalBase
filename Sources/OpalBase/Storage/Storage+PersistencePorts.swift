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
        try await operations.walletSnapshotSaver(snapshot)
    }
    
    func loadWalletSnapshot() async throws -> Wallet.Snapshot? {
        try await operations.walletSnapshotLoader()
    }
    
    func saveAccountSnapshot(_ snapshot: Account.Snapshot, accountIdentifier: Data) async throws {
        try await operations.accountSnapshotSaver(snapshot, accountIdentifier)
    }
    
    func loadAccountSnapshot(accountIdentifier: Data) async throws -> Account.Snapshot? {
        try await operations.accountSnapshotLoader(accountIdentifier)
    }
    
    func saveAddressBookSnapshot(_ snapshot: Address.Book.Snapshot, accountIdentifier: Data) async throws {
        try await operations.addressBookSnapshotSaver(snapshot, accountIdentifier)
    }
    
    func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> Address.Book.Snapshot? {
        try await operations.addressBookSnapshotLoader(accountIdentifier)
    }
    
    func wipeAll() async throws {
        try await operations.wipeAllOperation()
    }
}

private struct SecureSecretOperationsPort: SecureSecretAccessPort {
    let operations: Storage.PersistenceSession.Operations
    
    func saveMnemonic(_ mnemonic: Storage.Mnemonic,
                      fallbackToPlaintext: Bool) async throws -> Storage.Security.ProtectionMode {
        try await operations.mnemonicSaver(mnemonic, fallbackToPlaintext)
    }
    
    func loadMnemonicState() async throws -> (mnemonic: Storage.Mnemonic, protectionMode: Storage.Security.ProtectionMode)? {
        try await operations.mnemonicStateLoader()
    }
}
