// OpalBase+Storage+Ports~Persistence.swift

import Foundation

extension _OpalBase.Storage.Ports {
    init(operations: OpalBase.Storage.PersistenceSession.Operations) {
        self.init(snapshotPersistence: SnapshotOperationsAdapter(operations: operations),
                  secretAccess: SecureSecretOperationsAdapter(operations: operations))
    }
}

private struct SnapshotOperationsAdapter: OpalBase.Storage.SnapshotClient {
    let operations: OpalBase.Storage.PersistenceSession.Operations
    
    func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot) async throws {
        try await operations.walletSnapshotSaver(snapshot)
    }
    
    func loadWalletSnapshot() async throws -> OpalBase.Wallet.Snapshot? {
        try await operations.walletSnapshotLoader()
    }
    
    func saveAccountSnapshot(_ snapshot: OpalBase.Account.Snapshot, accountIdentifier: Data) async throws {
        try await operations.accountSnapshotSaver(snapshot, accountIdentifier)
    }
    
    func loadAccountSnapshot(accountIdentifier: Data) async throws -> OpalBase.Account.Snapshot? {
        try await operations.accountSnapshotLoader(accountIdentifier)
    }
    
    func saveAddressBookSnapshot(_ snapshot: OpalBase.Address.Book.Snapshot, accountIdentifier: Data) async throws {
        try await operations.addressBookSnapshotSaver(snapshot, accountIdentifier)
    }
    
    func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> OpalBase.Address.Book.Snapshot? {
        try await operations.addressBookSnapshotLoader(accountIdentifier)
    }
    
    func wipeAll() async throws {
        try await operations.wipeAllOperation()
    }
}

private struct SecureSecretOperationsAdapter: OpalBase.Storage.MnemonicSecretClient {
    let operations: OpalBase.Storage.PersistenceSession.Operations
    
    func saveMnemonic(_ mnemonic: OpalBase.Storage.Mnemonic,
                      fallbackToPlaintext: Bool) async throws -> OpalBase.Storage.Security.ProtectionMode {
        try await operations.mnemonicSaver(mnemonic, fallbackToPlaintext)
    }
    
    func loadMnemonicState() async throws -> (mnemonic: OpalBase.Storage.Mnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)? {
        try await operations.mnemonicStateLoader()
    }
}
