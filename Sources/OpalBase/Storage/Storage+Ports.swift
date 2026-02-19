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

extension Storage: SnapshotPersistencePort {}
extension Storage: SecureSecretAccessPort {}
