// OpalBase.Storage+PortsModel.swift

import Foundation

extension _OpalBase.Storage {
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

extension _OpalBase.Storage: SnapshotPersistenceAdapter {}
extension _OpalBase.Storage: SecureSecretAccessAdapter {}
