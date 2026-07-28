// OpalBase+Storage+SnapshotPersistence.swift

import Foundation

extension _OpalBase.Storage {
    /// Coordinated snapshot persistence closures.
    ///
    /// All values intentionally share a process-wide coordinator so separately
    /// constructed storage, snapshot, and mnemonic facades are safe to combine.
    /// Custom backend closures run inside coordination and must not reenter
    /// public persistence operations.
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
            try await performExclusively {
                try await saveWalletSnapshotAssumingExclusiveAccess(
                    snapshot,
                    generation: generation
                )
            }
        }

        public func loadWalletSnapshot(generation: String) async throws -> OpalBase.Wallet.Snapshot? {
            try await performExclusively {
                try await loadWalletSnapshotAssumingExclusiveAccess(generation: generation)
            }
        }

        public func deleteWalletSnapshot(generation: String) async throws {
            try await performExclusively {
                try await deleteWalletSnapshotAssumingExclusiveAccess(generation: generation)
            }
        }

        public func saveCommittedGeneration(_ generation: String) async throws {
            try await performExclusively {
                try await saveCommittedGenerationAssumingExclusiveAccess(generation)
            }
        }

        public func loadCommittedGeneration() async throws -> String? {
            try await performExclusively {
                try await loadCommittedGenerationAssumingExclusiveAccess()
            }
        }

        public func deleteCommittedGeneration() async throws {
            try await performExclusively {
                try await deleteCommittedGenerationAssumingExclusiveAccess()
            }
        }

        // Call only while holding operation access.
        func saveWalletSnapshotAssumingExclusiveAccess(
            _ snapshot: OpalBase.Wallet.Snapshot,
            generation: String
        ) async throws {
            try await performSaveWalletSnapshot(snapshot, generation)
        }

        func loadWalletSnapshotAssumingExclusiveAccess(
            generation: String
        ) async throws -> OpalBase.Wallet.Snapshot? {
            try await performLoadWalletSnapshot(generation)
        }

        func deleteWalletSnapshotAssumingExclusiveAccess(generation: String) async throws {
            try await performDeleteWalletSnapshot(generation)
        }

        func saveCommittedGenerationAssumingExclusiveAccess(_ generation: String) async throws {
            try await performSaveCommittedGeneration(generation)
        }

        func loadCommittedGenerationAssumingExclusiveAccess() async throws -> String? {
            try await performLoadCommittedGeneration()
        }

        func deleteCommittedGenerationAssumingExclusiveAccess() async throws {
            try await performDeleteCommittedGeneration()
        }

        func performExclusively<Result: Sendable>(
            _ operation: @Sendable () async throws -> Result
        ) async rethrows -> Result {
            try await PersistenceOperationCoordinator.processWideCoordinator.performExclusively(operation)
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
