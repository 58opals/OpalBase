// OpalBase+Storage+PersistenceSession.swift

import Foundation
import Synchronization

extension _OpalBase.Storage {
    public struct PersistenceSession: Sendable {
        /// Receives each began event before exclusive access is acquired.
        /// Later events are delivered in order after backend access is released.
        public typealias ProgressHandler = @Sendable (Progress) async -> Void
        /// Runs inside exclusive wipe coordination so key reset stays atomic.
        /// The callback must not reenter save, restore, wipe, or `wipeAll()`.
        public typealias ProtectedMaterialReset = @Sendable () async throws -> Void
        
        private let snapshotPersistence: OpalBase.Storage.SnapshotPersistence
        private let storedMnemonicPersistence: OpalBase.Storage.StoredMnemonicPersistence
        private let progressHandler: ProgressHandler
        let protectedMaterialReset: ProtectedMaterialReset?
        
        public init(
            storage: OpalBase.Storage,
            progressHandler: @escaping ProgressHandler = { _ in }
        ) async {
            let snapshotPersistence = await storage.makeSnapshotPersistence()
            let storedMnemonicPersistence = await storage.makeStoredMnemonicPersistence()
            self.init(
                snapshotPersistence: snapshotPersistence,
                storedMnemonicPersistence: storedMnemonicPersistence,
                progressHandler: progressHandler,
                protectedMaterialReset: {
                    try await storage.resetProtectedMaterial()
                }
            )
        }
        
        public init(snapshotPersistence: OpalBase.Storage.SnapshotPersistence,
                    storedMnemonicPersistence: OpalBase.Storage.StoredMnemonicPersistence,
                    progressHandler: @escaping ProgressHandler = { _ in },
                    protectedMaterialReset: ProtectedMaterialReset? = nil) {
            self.snapshotPersistence = snapshotPersistence
            self.storedMnemonicPersistence = storedMnemonicPersistence
            self.progressHandler = progressHandler
            self.protectedMaterialReset = protectedMaterialReset
        }
        
        @discardableResult
        public func save(wallet: OpalBase.Wallet, fallbackToPlaintext: Bool = true) async throws -> OpalBase.Storage.Security.ProtectionMode {
            try await save(
                wallet: wallet,
                policy: fallbackToPlaintext ? .legacyFallbackToPlaintext : .acceptProviderOutput
            )
        }

        @discardableResult
        public func save(
            wallet: OpalBase.Wallet,
            policy: OpalBase.Storage.Security.PersistencePolicy
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            let snapshot = await wallet.makeSnapshot()
            let walletMnemonic = wallet.mnemonic
            let passphrase = wallet.passphrase
            let mnemonic = OpalBase.Storage.StoredMnemonic(
                words: walletMnemonic.words.map(\.text),
                passphrase: passphrase
            )
            return try await save(
                snapshot: snapshot,
                mnemonic: mnemonic,
                policy: policy
            )
        }
        
        @discardableResult
        func save(
            snapshot: OpalBase.Wallet.Snapshot,
            mnemonic: OpalBase.Storage.StoredMnemonic,
            fallbackToPlaintext: Bool = true
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            try await save(
                snapshot: snapshot,
                mnemonic: mnemonic,
                policy: fallbackToPlaintext ? .legacyFallbackToPlaintext : .acceptProviderOutput
            )
        }

        @discardableResult
        func save(
            snapshot: OpalBase.Wallet.Snapshot,
            mnemonic: OpalBase.Storage.StoredMnemonic,
            policy: OpalBase.Storage.Security.PersistencePolicy
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            await progressHandler(.beganSave)
            return try await performPersistenceOperation { recordProgress in
                try await saveExclusively(
                    snapshot: snapshot,
                    mnemonic: mnemonic,
                    policy: policy,
                    recordProgress: recordProgress
                )
            }
        }

        private func saveExclusively(
            snapshot: OpalBase.Wallet.Snapshot,
            mnemonic: OpalBase.Storage.StoredMnemonic,
            policy: OpalBase.Storage.Security.PersistencePolicy,
            recordProgress: @Sendable (Progress) -> Void
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            let previousCommittedGeneration =
                try await snapshotPersistence.loadCommittedGenerationAssumingExclusiveAccess()
            let stagedGeneration = UUID().uuidString.lowercased()

            do {
                try await snapshotPersistence.saveWalletSnapshotAssumingExclusiveAccess(
                    snapshot,
                    generation: stagedGeneration
                )
                recordProgress(.savedWalletSnapshot(generation: stagedGeneration))

                let protectionMode =
                    try await storedMnemonicPersistence.saveMnemonicAssumingExclusiveAccess(
                        mnemonic,
                        generation: stagedGeneration,
                        policy: policy
                    )
                recordProgress(.savedMnemonic(mode: protectionMode))

                try await snapshotPersistence.saveCommittedGenerationAssumingExclusiveAccess(
                    stagedGeneration
                )
                recordProgress(.committedGeneration(generation: stagedGeneration))

                if let previousCommittedGeneration, previousCommittedGeneration != stagedGeneration {
                    await deleteGenerationArtifacts(previousCommittedGeneration)
                }

                recordProgress(.finishedSave(mode: protectionMode))
                return protectionMode
            } catch {
                let saveError = error
                let canDeleteStagedArtifacts = await restoreCommittedGenerationIfNeeded(
                    stagedGeneration: stagedGeneration,
                    previousCommittedGeneration: previousCommittedGeneration
                )
                if canDeleteStagedArtifacts {
                    await deleteGenerationArtifacts(stagedGeneration)
                }
                throw saveError
            }
        }
        
        public func restore() async throws -> RestoredState {
            await progressHandler(.beganRestore)
            return try await performPersistenceOperation { recordProgress in
                try await restoreExclusively(recordProgress: recordProgress)
            }
        }

        private func restoreExclusively(
            recordProgress: @Sendable (Progress) -> Void
        ) async throws -> RestoredState {
            let committedGeneration =
                try await snapshotPersistence.loadCommittedGenerationAssumingExclusiveAccess()
            let walletSnapshot: OpalBase.Wallet.Snapshot?
            let mnemonicState: (
                mnemonic: OpalBase.Storage.StoredMnemonic,
                protectionMode: OpalBase.Storage.Security.ProtectionMode
            )?

            if let committedGeneration {
                walletSnapshot =
                    try await snapshotPersistence.loadWalletSnapshotAssumingExclusiveAccess(
                        generation: committedGeneration
                    )
                do {
                    mnemonicState =
                        try await storedMnemonicPersistence.loadMnemonicStateAssumingExclusiveAccess(
                            generation: committedGeneration
                        )
                } catch {
                    guard storedMnemonicPersistence.isRecoverableLoadFailure(error) else {
                        throw error
                    }
                    mnemonicState = nil
                }
            } else {
                walletSnapshot = nil
                mnemonicState = nil
            }
            recordProgress(.loadedWalletSnapshot(found: walletSnapshot != nil))
            recordProgress(.loadedMnemonic(mode: mnemonicState?.protectionMode))
            recordProgress(.finishedRestore)
            
            return RestoredState(
                walletSnapshot: walletSnapshot,
                mnemonic: mnemonicState?.mnemonic,
                mnemonicProtectionMode: mnemonicState?.protectionMode
            )
        }
        
        public func wipe() async throws {
            await progressHandler(.beganWipe)
            try await performPersistenceOperation { recordProgress in
                try await wipeExclusively(recordProgress: recordProgress)
            }
        }

        private func wipeExclusively(
            recordProgress: @Sendable (Progress) -> Void
        ) async throws {
            do {
                try await deletePersistedWalletState()
            } catch {
                try? await protectedMaterialReset?()
                throw error
            }
            try await protectedMaterialReset?()
            recordProgress(.finishedWipe)
        }

        private func performPersistenceOperation<Result: Sendable>(
            _ operation: @escaping @Sendable (
                @Sendable (Progress) -> Void
            ) async throws -> Result
        ) async throws -> Result {
            let recordedProgressEvents = Mutex<[Progress]>(.init())

            do {
                let result = try await snapshotPersistence.performExclusively {
                    try await operation { progress in
                        recordedProgressEvents.withLock { events in
                            events.append(progress)
                        }
                    }
                }
                await deliverProgress(recordedProgressEvents.withLock { $0 })
                return result
            } catch {
                await deliverProgress(recordedProgressEvents.withLock { $0 })
                throw error
            }
        }

        private func deliverProgress(_ events: [Progress]) async {
            for event in events {
                await progressHandler(event)
            }
        }

        private func deletePersistedWalletState() async throws {
            if let committedGeneration =
                try await snapshotPersistence.loadCommittedGenerationAssumingExclusiveAccess()
            {
                try await snapshotPersistence.deleteCommittedGenerationAssumingExclusiveAccess()
                if let deletionError = await deleteGenerationArtifacts(committedGeneration) {
                    throw deletionError
                }
            } else {
                try await snapshotPersistence.deleteCommittedGenerationAssumingExclusiveAccess()
            }
        }

        private func restoreCommittedGenerationIfNeeded(
            stagedGeneration: String,
            previousCommittedGeneration: String?
        ) async -> Bool {
            let committedGeneration: String?
            do {
                committedGeneration =
                    try await snapshotPersistence.loadCommittedGenerationAssumingExclusiveAccess()
            } catch {
                return false
            }

            guard committedGeneration == stagedGeneration else {
                return true
            }

            if let previousCommittedGeneration {
                try? await snapshotPersistence.saveCommittedGenerationAssumingExclusiveAccess(
                    previousCommittedGeneration
                )
            } else {
                try? await snapshotPersistence.deleteCommittedGenerationAssumingExclusiveAccess()
            }

            do {
                return try await snapshotPersistence
                    .loadCommittedGenerationAssumingExclusiveAccess() != stagedGeneration
            } catch {
                return false
            }
        }

        @discardableResult
        private func deleteGenerationArtifacts(_ generation: String) async -> Swift.Error? {
            var deletionError: Swift.Error?
            do {
                try await snapshotPersistence.deleteWalletSnapshotAssumingExclusiveAccess(
                    generation: generation
                )
            } catch {
                deletionError = error
            }
            do {
                try await storedMnemonicPersistence.deleteMnemonicAssumingExclusiveAccess(
                    generation: generation
                )
            } catch {
                if deletionError == nil {
                    deletionError = error
                }
            }
            return deletionError
        }
    }
}

extension _OpalBase.Storage.PersistenceSession {
    public enum Progress: Sendable, Equatable {
        case beganSave
        case savedWalletSnapshot(generation: String)
        case savedMnemonic(mode: OpalBase.Storage.Security.ProtectionMode)
        case committedGeneration(generation: String)
        case finishedSave(mode: OpalBase.Storage.Security.ProtectionMode)
        case beganRestore
        case loadedWalletSnapshot(found: Bool)
        case loadedMnemonic(mode: OpalBase.Storage.Security.ProtectionMode?)
        case finishedRestore
        case beganWipe
        case finishedWipe
    }
    
    public struct RestoredState: Sendable {
        public let walletSnapshot: OpalBase.Wallet.Snapshot?
        public let mnemonic: OpalBase.Storage.StoredMnemonic?
        public let mnemonicProtectionMode: OpalBase.Storage.Security.ProtectionMode?
        
        public init(
            walletSnapshot: OpalBase.Wallet.Snapshot?,
            mnemonic: OpalBase.Storage.StoredMnemonic?,
            mnemonicProtectionMode: OpalBase.Storage.Security.ProtectionMode?
        ) {
            self.walletSnapshot = walletSnapshot
            self.mnemonic = mnemonic
            self.mnemonicProtectionMode = mnemonicProtectionMode
        }
    }
}
