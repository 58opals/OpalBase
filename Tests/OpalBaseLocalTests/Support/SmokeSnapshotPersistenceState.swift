// SmokeSnapshotPersistenceState.swift

@testable import OpalBase

actor SmokeSnapshotPersistenceState {
    private var walletSnapshots: [String: OpalBase.Wallet.Snapshot] = [:]
    private var committedGeneration: String?

    func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot, generation: String) {
        walletSnapshots[generation] = snapshot
    }

    func loadWalletSnapshot(generation: String) -> OpalBase.Wallet.Snapshot? {
        walletSnapshots[generation]
    }

    func deleteWalletSnapshot(generation: String) {
        walletSnapshots.removeValue(forKey: generation)
    }

    func saveCommittedGeneration(_ generation: String) {
        committedGeneration = generation
    }

    func loadCommittedGeneration() -> String? {
        committedGeneration
    }

    func deleteCommittedGeneration() {
        committedGeneration = nil
    }

    func wipeAll() {
        walletSnapshots.removeAll()
        committedGeneration = nil
    }
}
