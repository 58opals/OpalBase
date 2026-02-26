// StorageActor+PortsModel.swift

import Foundation

extension StorageActor {
    public struct PortsModel: Sendable {
        public let snapshotPersistence: any SnapshotPersistenceAdapter
        public let secretAccess: any SecureSecretAccessAdapter

        public init(snapshotPersistence: any SnapshotPersistenceAdapter,
                    secretAccess: any SecureSecretAccessAdapter) {
            self.snapshotPersistence = snapshotPersistence
            self.secretAccess = secretAccess
        }
    }

    public nonisolated func makePorts() -> PortsModel {
        PortsModel(snapshotPersistence: self, secretAccess: self)
    }
}

extension StorageActor: SnapshotPersistenceAdapter {}
extension StorageActor: SecureSecretAccessAdapter {}
