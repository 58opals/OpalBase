// OpalBase+Storage+StoredMnemonicPersistence.swift

import Foundation

extension _OpalBase.Storage {
    /// Coordinated stored-mnemonic persistence closures.
    ///
    /// All values share the process-wide persistence coordinator. Backend
    /// closures run inside coordination and must not reenter public persistence
    /// operations.
    public struct StoredMnemonicPersistence: Sendable {
        private let performSaveMnemonic: @Sendable (
            OpalBase.Storage.StoredMnemonic,
            String
        ) async throws -> OpalBase.Storage.Security.ProtectionMode
        private let performLoadMnemonicState: @Sendable (String) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?
        private let performDeleteMnemonic: @Sendable (String) async throws -> Void
        private let isLoadFailureRecoverable: @Sendable (Swift.Error) -> Bool

        /// Creates one custom mnemonic-persistence root with an immutable write policy.
        /// The save backend receives exactly that policy on every call.
        public init(
            secretPersistencePolicy: OpalBase.Storage.Security.PersistencePolicy,
            saveMnemonic: @escaping @Sendable (
                OpalBase.Storage.StoredMnemonic,
                String,
                OpalBase.Storage.Security.PersistencePolicy
            ) async throws -> OpalBase.Storage.Security.ProtectionMode,
            loadMnemonicState: @escaping @Sendable (String) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?,
            deleteMnemonic: @escaping @Sendable (String) async throws -> Void,
            recoverableLoadFailure: @escaping @Sendable (Swift.Error) -> Bool = { _ in false }
        ) {
            self.init(
                secretPersistencePolicy: secretPersistencePolicy,
                saveMnemonicUsingBoundPolicy: { mnemonic, generation in
                    try await saveMnemonic(
                        mnemonic,
                        generation,
                        secretPersistencePolicy
                    )
                },
                loadMnemonicState: loadMnemonicState,
                deleteMnemonic: deleteMnemonic,
                recoverableLoadFailure: recoverableLoadFailure
            )
        }

        fileprivate init(
            secretPersistencePolicy: OpalBase.Storage.Security.PersistencePolicy,
            saveMnemonicUsingBoundPolicy: @escaping @Sendable (
                OpalBase.Storage.StoredMnemonic,
                String
            ) async throws -> OpalBase.Storage.Security.ProtectionMode,
            loadMnemonicState: @escaping @Sendable (String) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?,
            deleteMnemonic: @escaping @Sendable (String) async throws -> Void,
            recoverableLoadFailure: @escaping @Sendable (Swift.Error) -> Bool
        ) {
            self.performSaveMnemonic = Self.makePolicyEnforcingSave(
                saveMnemonicUsingBoundPolicy,
                policy: secretPersistencePolicy,
                deleteMnemonic: deleteMnemonic
            )
            self.performLoadMnemonicState = loadMnemonicState
            self.performDeleteMnemonic = deleteMnemonic
            self.isLoadFailureRecoverable = recoverableLoadFailure
        }

        public func saveMnemonic(
            _ mnemonic: OpalBase.Storage.StoredMnemonic,
            generation: String
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            try await PersistenceOperationCoordinator.processWideCoordinator.performExclusively {
                try await saveMnemonicAssumingExclusiveAccess(
                    mnemonic,
                    generation: generation
                )
            }
        }

        public func loadMnemonicState(generation: String) async throws -> (
            mnemonic: OpalBase.Storage.StoredMnemonic,
            protectionMode: OpalBase.Storage.Security.ProtectionMode
        )? {
            try await PersistenceOperationCoordinator.processWideCoordinator.performExclusively {
                try await loadMnemonicStateAssumingExclusiveAccess(generation: generation)
            }
        }

        public func deleteMnemonic(generation: String) async throws {
            try await PersistenceOperationCoordinator.processWideCoordinator.performExclusively {
                try await deleteMnemonicAssumingExclusiveAccess(generation: generation)
            }
        }

        // Call only while holding operation access.
        func saveMnemonicAssumingExclusiveAccess(
            _ mnemonic: OpalBase.Storage.StoredMnemonic,
            generation: String
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            try await performSaveMnemonic(mnemonic, generation)
        }

        func loadMnemonicStateAssumingExclusiveAccess(generation: String) async throws -> (
            mnemonic: OpalBase.Storage.StoredMnemonic,
            protectionMode: OpalBase.Storage.Security.ProtectionMode
        )? {
            try await performLoadMnemonicState(generation)
        }

        func deleteMnemonicAssumingExclusiveAccess(generation: String) async throws {
            try await performDeleteMnemonic(generation)
        }

        func isRecoverableLoadFailure(_ error: Swift.Error) -> Bool {
            isLoadFailureRecoverable(error)
        }

        private static func makePolicyEnforcingSave(
            _ saveMnemonic: @escaping @Sendable (
                OpalBase.Storage.StoredMnemonic,
                String
            ) async throws -> OpalBase.Storage.Security.ProtectionMode,
            policy: OpalBase.Storage.Security.PersistencePolicy,
            deleteMnemonic: @escaping @Sendable (String) async throws -> Void
        ) -> @Sendable (
            OpalBase.Storage.StoredMnemonic,
            String
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            { mnemonic, generation in
                let protectionMode = try await saveMnemonic(mnemonic, generation)
                if policy == .requireSecureEnclave, protectionMode != .secureEnclave {
                    try await deleteMnemonic(generation)
                    throw OpalBase.Storage.Security.Error.insufficientProtection(
                        required: .secureEnclave,
                        actual: protectionMode
                    )
                }
                return protectionMode
            }
        }
    }

    public func makeStoredMnemonicPersistence() -> StoredMnemonicPersistence {
        let security = security
        let policy = secretPersistencePolicy
        return StoredMnemonicPersistence(
            secretPersistencePolicy: policy,
            saveMnemonicUsingBoundPolicy: { mnemonic, generation in
                try await self.saveMnemonic(
                    mnemonic,
                    generation: generation
                )
            },
            loadMnemonicState: loadMnemonicState(generation:),
            deleteMnemonic: deleteMnemonic(generation:),
            recoverableLoadFailure: { error in
                Self.isRecoverableMnemonicLoadFailure(error, security: security)
            }
        )
    }
}
