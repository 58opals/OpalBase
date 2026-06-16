// OpalBase+WalletSnapshotInteractor.swift

public extension OpalBase {
    /// Snapshot-only storage/import-export lane. This surface must not retain transport clients, raw transactions, or secrets.
    struct WalletSnapshotInteractor: Sendable {
        private let snapshotPersistence: OpalBase.Storage.SnapshotPersistence

        public init(snapshotPersistence: OpalBase.Storage.SnapshotPersistence) {
            self.snapshotPersistence = snapshotPersistence
        }

        public init(storage: OpalBase.Storage) async {
            self.snapshotPersistence = await storage.makeSnapshotPersistence()
        }

        public func makeSnapshot(from wallet: OpalBase.Wallet) async -> OpalBase.Wallet.Snapshot {
            await wallet.makeSnapshot()
        }

        public func applySnapshot(_ snapshot: OpalBase.Wallet.Snapshot, to wallet: OpalBase.Wallet) async throws {
            try await wallet.applySnapshot(snapshot)
        }

        public func saveSnapshot(_ snapshot: OpalBase.Wallet.Snapshot, generation: String) async throws {
            try await snapshotPersistence.saveWalletSnapshot(snapshot, generation: generation)
        }

        public func loadSnapshot(generation: String) async throws -> OpalBase.Wallet.Snapshot? {
            try await snapshotPersistence.loadWalletSnapshot(generation: generation)
        }

        public func deleteSnapshot(generation: String) async throws {
            try await snapshotPersistence.deleteWalletSnapshot(generation: generation)
        }

        public func saveCommittedGeneration(_ generation: String) async throws {
            try await snapshotPersistence.saveCommittedGeneration(generation)
        }

        public func loadCommittedGeneration() async throws -> String? {
            try await snapshotPersistence.loadCommittedGeneration()
        }

        public func deleteCommittedGeneration() async throws {
            try await snapshotPersistence.deleteCommittedGeneration()
        }
    }
}
