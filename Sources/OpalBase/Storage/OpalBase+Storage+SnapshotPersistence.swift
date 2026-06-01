// OpalBase+Storage+SnapshotPersistence.swift

import Foundation

extension _OpalBase.Storage {
    public struct SnapshotPersistence: Sendable {
        private let performSaveWalletSnapshot: @Sendable (OpalBase.Wallet.Snapshot, String) async throws -> Void
        private let performLoadWalletSnapshot: @Sendable (String) async throws -> OpalBase.Wallet.Snapshot?
        private let performDeleteWalletSnapshot: @Sendable (String) async throws -> Void
        private let performSaveCommittedGeneration: @Sendable (String) async throws -> Void
        private let performLoadCommittedGeneration: @Sendable () async throws -> String?
        private let performDeleteCommittedGeneration: @Sendable () async throws -> Void

        public init(
            saveWalletSnapshot: @escaping @Sendable (OpalBase.Wallet.Snapshot, String) async throws -> Void,
            loadWalletSnapshot: @escaping @Sendable (String) async throws -> OpalBase.Wallet.Snapshot?,
            deleteWalletSnapshot: @escaping @Sendable (String) async throws -> Void,
            saveCommittedGeneration: @escaping @Sendable (String) async throws -> Void,
            loadCommittedGeneration: @escaping @Sendable () async throws -> String?,
            deleteCommittedGeneration: @escaping @Sendable () async throws -> Void
        ) {
            self.performSaveWalletSnapshot = saveWalletSnapshot
            self.performLoadWalletSnapshot = loadWalletSnapshot
            self.performDeleteWalletSnapshot = deleteWalletSnapshot
            self.performSaveCommittedGeneration = saveCommittedGeneration
            self.performLoadCommittedGeneration = loadCommittedGeneration
            self.performDeleteCommittedGeneration = deleteCommittedGeneration
        }

        public func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot, generation: String) async throws {
            try await performSaveWalletSnapshot(snapshot, generation)
        }

        public func loadWalletSnapshot(generation: String) async throws -> OpalBase.Wallet.Snapshot? {
            try await performLoadWalletSnapshot(generation)
        }

        public func deleteWalletSnapshot(generation: String) async throws {
            try await performDeleteWalletSnapshot(generation)
        }

        public func saveCommittedGeneration(_ generation: String) async throws {
            try await performSaveCommittedGeneration(generation)
        }

        public func loadCommittedGeneration() async throws -> String? {
            try await performLoadCommittedGeneration()
        }

        public func deleteCommittedGeneration() async throws {
            try await performDeleteCommittedGeneration()
        }
    }

    public func makeSnapshotPersistence() -> SnapshotPersistence {
        SnapshotPersistence(
            saveWalletSnapshot: saveWalletSnapshot(_:generation:),
            loadWalletSnapshot: loadWalletSnapshot(generation:),
            deleteWalletSnapshot: deleteWalletSnapshot(generation:),
            saveCommittedGeneration: saveCommittedWalletSnapshotGeneration(_:),
            loadCommittedGeneration: loadCommittedWalletSnapshotGeneration,
            deleteCommittedGeneration: deleteCommittedWalletSnapshotGeneration
        )
    }
}
