// StorageActor+PersistencePorts.swift

import Foundation

extension StorageActor.PortsModel {
    init(operations: StorageActor.PersistenceSessionModel.OperationsModel) {
        self.init(snapshotPersistence: SnapshotOperationsAdapter(operations: operations),
                  secretAccess: SecureSecretOperationsAdapter(operations: operations))
    }
}

private struct SnapshotOperationsAdapter: SnapshotPersistenceAdapter {
    let operations: StorageActor.PersistenceSessionModel.OperationsModel
    
    func saveWalletSnapshot(_ snapshot: WalletActor.SnapshotModel) async throws {
        try await operations.walletSnapshotSaver(snapshot)
    }
    
    func loadWalletSnapshot() async throws -> WalletActor.SnapshotModel? {
        try await operations.walletSnapshotLoader()
    }
    
    func saveAccountSnapshot(_ snapshot: AccountActor.SnapshotModel, accountIdentifier: Data) async throws {
        try await operations.accountSnapshotSaver(snapshot, accountIdentifier)
    }
    
    func loadAccountSnapshot(accountIdentifier: Data) async throws -> AccountActor.SnapshotModel? {
        try await operations.accountSnapshotLoader(accountIdentifier)
    }
    
    func saveAddressBookSnapshot(_ snapshot: AddressModel.BookActor.SnapshotModel, accountIdentifier: Data) async throws {
        try await operations.addressBookSnapshotSaver(snapshot, accountIdentifier)
    }
    
    func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> AddressModel.BookActor.SnapshotModel? {
        try await operations.addressBookSnapshotLoader(accountIdentifier)
    }
    
    func wipeAll() async throws {
        try await operations.wipeAllOperation()
    }
}

private struct SecureSecretOperationsAdapter: SecureSecretAccessAdapter {
    let operations: StorageActor.PersistenceSessionModel.OperationsModel
    
    func saveMnemonic(_ mnemonic: StorageActor.MnemonicModel,
                      fallbackToPlaintext: Bool) async throws -> StorageActor.SecurityModel.ProtectionMode {
        try await operations.mnemonicSaver(mnemonic, fallbackToPlaintext)
    }
    
    func loadMnemonicState() async throws -> (mnemonic: StorageActor.MnemonicModel, protectionMode: StorageActor.SecurityModel.ProtectionMode)? {
        try await operations.mnemonicStateLoader()
    }
}
