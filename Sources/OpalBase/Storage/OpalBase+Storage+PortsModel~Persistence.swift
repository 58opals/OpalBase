// OpalBase.Storage+PortsModel~Persistence.swift

import Foundation

extension _OpalBase.Storage.PortsModel {
    init(operations: OpalBase.Storage.PersistenceSessionModel.OperationsModel) {
        self.init(snapshotPersistence: SnapshotOperationsAdapter(operations: operations),
                  secretAccess: SecureSecretOperationsAdapter(operations: operations))
    }
}

private struct SnapshotOperationsAdapter: SnapshotPersistenceAdapter {
    let operations: OpalBase.Storage.PersistenceSessionModel.OperationsModel
    
    func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot) async throws {
        try await operations.walletSnapshotSaver(snapshot)
    }
    
    func loadWalletSnapshot() async throws -> OpalBase.Wallet.Snapshot? {
        try await operations.walletSnapshotLoader()
    }
    
    func saveAccountSnapshot(_ snapshot: OpalBase.Account.SnapshotModel, accountIdentifier: Data) async throws {
        try await operations.accountSnapshotSaver(snapshot, accountIdentifier)
    }
    
    func loadAccountSnapshot(accountIdentifier: Data) async throws -> OpalBase.Account.SnapshotModel? {
        try await operations.accountSnapshotLoader(accountIdentifier)
    }
    
    func saveAddressBookSnapshot(_ snapshot: OpalBase.Address.Book.SnapshotModel, accountIdentifier: Data) async throws {
        try await operations.addressBookSnapshotSaver(snapshot, accountIdentifier)
    }
    
    func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> OpalBase.Address.Book.SnapshotModel? {
        try await operations.addressBookSnapshotLoader(accountIdentifier)
    }
    
    func wipeAll() async throws {
        try await operations.wipeAllOperation()
    }
}

private struct SecureSecretOperationsAdapter: SecureSecretAccessAdapter {
    let operations: OpalBase.Storage.PersistenceSessionModel.OperationsModel
    
    func saveMnemonic(_ mnemonic: OpalBase.Storage.Mnemonic,
                      fallbackToPlaintext: Bool) async throws -> OpalBase.Storage.SecurityModel.ProtectionMode {
        try await operations.mnemonicSaver(mnemonic, fallbackToPlaintext)
    }
    
    func loadMnemonicState() async throws -> (mnemonic: OpalBase.Storage.Mnemonic, protectionMode: OpalBase.Storage.SecurityModel.ProtectionMode)? {
        try await operations.mnemonicStateLoader()
    }
}
