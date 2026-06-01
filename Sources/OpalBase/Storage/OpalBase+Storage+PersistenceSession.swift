// OpalBase+Storage+PersistenceSession.swift

import Foundation

extension _OpalBase.Storage {
    public struct PersistenceSession: Sendable {
        public typealias ProgressHandler = @Sendable (Progress) async -> Void
        
        private let snapshotPersistence: OpalBase.Storage.SnapshotPersistence
        private let storedMnemonicPersistence: OpalBase.Storage.StoredMnemonicPersistence
        private let progressHandler: ProgressHandler
        
        public init(
            storage: OpalBase.Storage,
            progressHandler: @escaping ProgressHandler = { _ in }
        ) async {
            let snapshotPersistence = await storage.makeSnapshotPersistence()
            let storedMnemonicPersistence = await storage.makeStoredMnemonicPersistence()
            self.init(
                snapshotPersistence: snapshotPersistence,
                storedMnemonicPersistence: storedMnemonicPersistence,
                progressHandler: progressHandler
            )
        }
        
        public init(snapshotPersistence: OpalBase.Storage.SnapshotPersistence,
                    storedMnemonicPersistence: OpalBase.Storage.StoredMnemonicPersistence,
                    progressHandler: @escaping ProgressHandler = { _ in }) {
            self.snapshotPersistence = snapshotPersistence
            self.storedMnemonicPersistence = storedMnemonicPersistence
            self.progressHandler = progressHandler
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
            let previousCommittedGeneration = try await snapshotPersistence.loadCommittedGeneration()
            let stagedGeneration = UUID().uuidString.lowercased()

            do {
                try await snapshotPersistence.saveWalletSnapshot(snapshot, generation: stagedGeneration)
                await progressHandler(.savedWalletSnapshot(generation: stagedGeneration))

                let protectionMode = try await storedMnemonicPersistence.saveMnemonic(
                    mnemonic,
                    generation: stagedGeneration,
                    policy: policy
                )
                await progressHandler(.savedMnemonic(mode: protectionMode))

                try await snapshotPersistence.saveCommittedGeneration(stagedGeneration)
                await progressHandler(.committedGeneration(generation: stagedGeneration))

                if let previousCommittedGeneration, previousCommittedGeneration != stagedGeneration {
                    try? await snapshotPersistence.deleteWalletSnapshot(generation: previousCommittedGeneration)
                    try? await storedMnemonicPersistence.deleteMnemonic(generation: previousCommittedGeneration)
                }

                await progressHandler(.finishedSave(mode: protectionMode))
                return protectionMode
            } catch {
                try? await snapshotPersistence.deleteWalletSnapshot(generation: stagedGeneration)
                try? await storedMnemonicPersistence.deleteMnemonic(generation: stagedGeneration)
                throw error
            }
        }
        
        public func restore() async throws -> RestoredState {
            await progressHandler(.beganRestore)
            let committedGeneration = try await snapshotPersistence.loadCommittedGeneration()
            let walletSnapshot: OpalBase.Wallet.Snapshot?
            let mnemonicState: (
                mnemonic: OpalBase.Storage.StoredMnemonic,
                protectionMode: OpalBase.Storage.Security.ProtectionMode
            )?

            if let committedGeneration {
                walletSnapshot = try await snapshotPersistence.loadWalletSnapshot(generation: committedGeneration)
                do {
                    mnemonicState = try await storedMnemonicPersistence.loadMnemonicState(
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
            await progressHandler(.loadedWalletSnapshot(found: walletSnapshot != nil))
            await progressHandler(.loadedMnemonic(mode: mnemonicState?.protectionMode))
            await progressHandler(.finishedRestore)
            
            return RestoredState(
                walletSnapshot: walletSnapshot,
                mnemonic: mnemonicState?.mnemonic,
                mnemonicProtectionMode: mnemonicState?.protectionMode
            )
        }
        
        public func wipe() async throws {
            await progressHandler(.beganWipe)
            if let committedGeneration = try await snapshotPersistence.loadCommittedGeneration() {
                try await snapshotPersistence.deleteCommittedGeneration()
                var deletionError: Swift.Error?
                do {
                    try await snapshotPersistence.deleteWalletSnapshot(generation: committedGeneration)
                } catch {
                    deletionError = error
                }
                do {
                    try await storedMnemonicPersistence.deleteMnemonic(generation: committedGeneration)
                } catch {
                    if deletionError == nil {
                        deletionError = error
                    }
                }
                if let deletionError {
                    throw deletionError
                }
            } else {
                try await snapshotPersistence.deleteCommittedGeneration()
            }
            await progressHandler(.finishedWipe)
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
