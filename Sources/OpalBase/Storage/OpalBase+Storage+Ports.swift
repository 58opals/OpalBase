// OpalBase+Storage+Ports.swift

import Foundation

extension _OpalBase.Storage {
    public struct Ports: Sendable {
        public let snapshotPersistence: any OpalBase.Storage.SnapshotStore
        public let secretAccess: any OpalBase.Storage.MnemonicSecretStore

        public init(snapshotPersistence: any OpalBase.Storage.SnapshotStore,
                    secretAccess: any OpalBase.Storage.MnemonicSecretStore) {
            self.snapshotPersistence = snapshotPersistence
            self.secretAccess = secretAccess
        }
    }

    public nonisolated func makePorts() -> Ports {
        Ports(snapshotPersistence: self, secretAccess: self)
    }
}

extension _OpalBase.Storage: OpalBase.Storage.SnapshotStore {}
extension _OpalBase.Storage: OpalBase.Storage.MnemonicSecretStore {}
