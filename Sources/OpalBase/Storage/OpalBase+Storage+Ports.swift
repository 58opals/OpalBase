// OpalBase+Storage+Ports.swift

import Foundation

extension _OpalBase.Storage {
    public struct Ports: Sendable {
        public let snapshotPersistence: any OpalBase.Storage.SnapshotClient
        public let secretAccess: any OpalBase.Storage.MnemonicSecretClient

        public init(snapshotPersistence: any OpalBase.Storage.SnapshotClient,
                    secretAccess: any OpalBase.Storage.MnemonicSecretClient) {
            self.snapshotPersistence = snapshotPersistence
            self.secretAccess = secretAccess
        }
    }

    public nonisolated func makePorts() -> Ports {
        Ports(snapshotPersistence: self, secretAccess: self)
    }
}

extension _OpalBase.Storage: OpalBase.Storage.SnapshotClient {}
extension _OpalBase.Storage: OpalBase.Storage.MnemonicSecretClient {}
