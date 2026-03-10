// OpalBase+Storage+SnapshotStore.swift

import Foundation

extension _OpalBase.Storage {
    public struct SnapshotStore: Sendable {
        private let saveWalletSnapshotHandler: @Sendable (OpalBase.Wallet.Snapshot, String) async throws -> Void
        private let loadWalletSnapshotHandler: @Sendable (String) async throws -> OpalBase.Wallet.Snapshot?
        private let deleteWalletSnapshotHandler: @Sendable (String) async throws -> Void
        private let saveCommittedGenerationHandler: @Sendable (String) async throws -> Void
        private let loadCommittedGenerationHandler: @Sendable () async throws -> String?
        private let deleteCommittedGenerationHandler: @Sendable () async throws -> Void

        public init(
            saveWalletSnapshot: @escaping @Sendable (OpalBase.Wallet.Snapshot, String) async throws -> Void,
            loadWalletSnapshot: @escaping @Sendable (String) async throws -> OpalBase.Wallet.Snapshot?,
            deleteWalletSnapshot: @escaping @Sendable (String) async throws -> Void,
            saveCommittedGeneration: @escaping @Sendable (String) async throws -> Void,
            loadCommittedGeneration: @escaping @Sendable () async throws -> String?,
            deleteCommittedGeneration: @escaping @Sendable () async throws -> Void
        ) {
            self.saveWalletSnapshotHandler = saveWalletSnapshot
            self.loadWalletSnapshotHandler = loadWalletSnapshot
            self.deleteWalletSnapshotHandler = deleteWalletSnapshot
            self.saveCommittedGenerationHandler = saveCommittedGeneration
            self.loadCommittedGenerationHandler = loadCommittedGeneration
            self.deleteCommittedGenerationHandler = deleteCommittedGeneration
        }

        public func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot, generation: String) async throws {
            try await saveWalletSnapshotHandler(snapshot, generation)
        }

        public func loadWalletSnapshot(generation: String) async throws -> OpalBase.Wallet.Snapshot? {
            try await loadWalletSnapshotHandler(generation)
        }

        public func deleteWalletSnapshot(generation: String) async throws {
            try await deleteWalletSnapshotHandler(generation)
        }

        public func saveCommittedGeneration(_ generation: String) async throws {
            try await saveCommittedGenerationHandler(generation)
        }

        public func loadCommittedGeneration() async throws -> String? {
            try await loadCommittedGenerationHandler()
        }

        public func deleteCommittedGeneration() async throws {
            try await deleteCommittedGenerationHandler()
        }
    }

    public nonisolated func makeSnapshotStore() -> SnapshotStore {
        SnapshotStore(
            saveWalletSnapshot: saveWalletSnapshot(_:generation:),
            loadWalletSnapshot: loadWalletSnapshot(generation:),
            deleteWalletSnapshot: deleteWalletSnapshot(generation:),
            saveCommittedGeneration: saveCommittedWalletSnapshotGeneration(_:),
            loadCommittedGeneration: loadCommittedWalletSnapshotGeneration,
            deleteCommittedGeneration: deleteCommittedWalletSnapshotGeneration
        )
    }
}
