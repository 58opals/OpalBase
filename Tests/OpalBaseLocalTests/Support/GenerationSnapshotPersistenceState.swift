// GenerationSnapshotPersistenceState.swift

@testable import OpalBase

actor GenerationSnapshotPersistenceState {
    private var walletSnapshots: [String: OpalBase.Wallet.Snapshot] = .init()
    private var committedGeneration: String?
    private var committedGenerationSaveMutationBeforeFailureFlags: [Bool] = .init()
    private var shouldBlockNextWalletSnapshotSave = false
    private var hasWalletSnapshotSaveReachedBlock = false
    private var isBlockedWalletSnapshotSaveReleased = false
    private var blockedWalletSnapshotSaveContinuation: CheckedContinuation<Void, Never>?
    private var walletSnapshotSaveBlockWaiters: [CheckedContinuation<Void, Never>] = .init()

    func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot, generation: String) async {
        if shouldBlockNextWalletSnapshotSave {
            shouldBlockNextWalletSnapshotSave = false
            hasWalletSnapshotSaveReachedBlock = true

            let waiters = walletSnapshotSaveBlockWaiters
            walletSnapshotSaveBlockWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }

            await withCheckedContinuation { continuation in
                if isBlockedWalletSnapshotSaveReleased {
                    continuation.resume()
                } else {
                    blockedWalletSnapshotSaveContinuation = continuation
                }
            }
        }

        walletSnapshots[generation] = snapshot
    }

    func loadWalletSnapshot(generation: String) -> OpalBase.Wallet.Snapshot? {
        walletSnapshots[generation]
    }

    func deleteWalletSnapshot(generation: String) {
        walletSnapshots.removeValue(forKey: generation)
    }

    func saveCommittedGeneration(_ generation: String) throws {
        if committedGenerationSaveMutationBeforeFailureFlags.first == false {
            committedGenerationSaveMutationBeforeFailureFlags.removeFirst()
            throw GenerationPersistenceError.simulatedFailure
        }

        committedGeneration = generation
        if committedGenerationSaveMutationBeforeFailureFlags.first == true {
            committedGenerationSaveMutationBeforeFailureFlags.removeFirst()
            throw GenerationPersistenceError.simulatedFailure
        }
    }

    func loadCommittedGeneration() -> String? {
        committedGeneration
    }

    func deleteCommittedGeneration() {
        committedGeneration = nil
    }

    func failNextCommittedGenerationSaveAfterMutation() {
        committedGenerationSaveMutationBeforeFailureFlags.append(true)
    }

    func failNextCommittedGenerationSaveBeforeMutation() {
        committedGenerationSaveMutationBeforeFailureFlags.append(false)
    }

    func blockNextWalletSnapshotSave() {
        shouldBlockNextWalletSnapshotSave = true
        hasWalletSnapshotSaveReachedBlock = false
        isBlockedWalletSnapshotSaveReleased = false
        blockedWalletSnapshotSaveContinuation = nil
    }

    func waitUntilWalletSnapshotSaveBlocks() async {
        guard !hasWalletSnapshotSaveReachedBlock else {
            return
        }

        await withCheckedContinuation { continuation in
            walletSnapshotSaveBlockWaiters.append(continuation)
        }
    }

    func releaseBlockedWalletSnapshotSave() {
        isBlockedWalletSnapshotSaveReleased = true
        blockedWalletSnapshotSaveContinuation?.resume()
        blockedWalletSnapshotSaveContinuation = nil
    }
}
