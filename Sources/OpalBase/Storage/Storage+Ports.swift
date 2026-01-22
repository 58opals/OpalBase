// Storage+Ports.swift

import Foundation

extension Storage {
    public struct Ports: Sendable {
        public let snapshotPersistence: any SnapshotPersistencePort
        public let secretAccess: any SecureSecretAccessPort
        
        public init(snapshotPersistence: any SnapshotPersistencePort,
                    secretAccess: any SecureSecretAccessPort) {
            self.snapshotPersistence = snapshotPersistence
            self.secretAccess = secretAccess
        }
    }
    
    public nonisolated func makePorts() -> Ports {
        Ports(snapshotPersistence: self, secretAccess: self)
    }
}

public protocol SnapshotPersistencePort: Sendable {
    func saveWalletSnapshot(_ snapshot: Wallet.Snapshot) async throws
    func loadWalletSnapshot() async throws -> Wallet.Snapshot?
    func saveAccountSnapshot(_ snapshot: Account.Snapshot, accountIdentifier: Data) async throws
    func loadAccountSnapshot(accountIdentifier: Data) async throws -> Account.Snapshot?
    func saveAddressBookSnapshot(_ snapshot: Address.Book.Snapshot, accountIdentifier: Data) async throws
    func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> Address.Book.Snapshot?
    func wipeAll() async throws
}

public protocol SecureSecretAccessPort: Sendable {
    func saveMnemonic(_ mnemonic: Storage.Mnemonic,
                      fallbackToPlaintext: Bool) async throws -> Storage.Security.ProtectionMode
    func loadMnemonicState() async throws -> (mnemonic: Storage.Mnemonic, protectionMode: Storage.Security.ProtectionMode)?
}

extension Storage: SnapshotPersistencePort {}
extension Storage: SecureSecretAccessPort {}
