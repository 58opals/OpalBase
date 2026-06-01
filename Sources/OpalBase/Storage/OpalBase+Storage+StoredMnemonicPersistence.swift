// OpalBase+Storage+StoredMnemonicPersistence.swift

import Foundation

private func isRecoverableStoredMnemonicLoadFailure(
    _ error: Swift.Error
) -> Bool {
    switch error {
    case OpalBase.Storage.Error.secureStoreFailure(let underlying),
        OpalBase.Storage.Security.Error.decryptionFailure(let underlying):
        return isRecoverableStoredMnemonicLoadFailure(underlying)
    default:
        break
    }

    let nsError = error as NSError
    return nsError.domain == NSOSStatusErrorDomain
        && nsError.code == Int(errSecItemNotFound)
}

extension _OpalBase.Storage {
    public struct StoredMnemonicPersistence: Sendable {
        private let performSaveMnemonic: @Sendable (
            OpalBase.Storage.StoredMnemonic,
            String,
            OpalBase.Storage.Security.PersistencePolicy
        ) async throws -> OpalBase.Storage.Security.ProtectionMode
        private let performLoadMnemonicState: @Sendable (String) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?
        private let performDeleteMnemonic: @Sendable (String) async throws -> Void
        private let isLoadFailureRecoverable: @Sendable (Swift.Error) -> Bool

        public init(
            saveMnemonic: @escaping @Sendable (OpalBase.Storage.StoredMnemonic, String, Bool) async throws -> OpalBase.Storage.Security.ProtectionMode,
            loadMnemonicState: @escaping @Sendable (String) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?,
            deleteMnemonic: @escaping @Sendable (String) async throws -> Void
        ) {
            let saveMnemonicWithPolicy: @Sendable (
                OpalBase.Storage.StoredMnemonic,
                String,
                OpalBase.Storage.Security.PersistencePolicy
            ) async throws -> OpalBase.Storage.Security.ProtectionMode = { mnemonic, generation, policy in
                try await saveMnemonic(
                    mnemonic,
                    generation,
                    policy == .legacyFallbackToPlaintext
                )
            }
            self.performSaveMnemonic = Self.makePolicyEnforcingSave(
                saveMnemonicWithPolicy,
                deleteMnemonic: deleteMnemonic
            )
            self.performLoadMnemonicState = loadMnemonicState
            self.performDeleteMnemonic = deleteMnemonic
            self.isLoadFailureRecoverable = { _ in false }
        }

        public init(
            saveMnemonicWithPolicy: @escaping @Sendable (
                OpalBase.Storage.StoredMnemonic,
                String,
                OpalBase.Storage.Security.PersistencePolicy
            ) async throws -> OpalBase.Storage.Security.ProtectionMode,
            loadMnemonicState: @escaping @Sendable (String) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?,
            deleteMnemonic: @escaping @Sendable (String) async throws -> Void
        ) {
            self.performSaveMnemonic = Self.makePolicyEnforcingSave(
                saveMnemonicWithPolicy,
                deleteMnemonic: deleteMnemonic
            )
            self.performLoadMnemonicState = loadMnemonicState
            self.performDeleteMnemonic = deleteMnemonic
            self.isLoadFailureRecoverable = { _ in false }
        }

        init(
            saveMnemonicWithPolicy: @escaping @Sendable (
                OpalBase.Storage.StoredMnemonic,
                String,
                OpalBase.Storage.Security.PersistencePolicy
            ) async throws -> OpalBase.Storage.Security.ProtectionMode,
            loadMnemonicState: @escaping @Sendable (String) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?,
            deleteMnemonic: @escaping @Sendable (String) async throws -> Void,
            recoverableLoadFailure: @escaping @Sendable (Swift.Error) -> Bool
        ) {
            self.performSaveMnemonic = Self.makePolicyEnforcingSave(
                saveMnemonicWithPolicy,
                deleteMnemonic: deleteMnemonic
            )
            self.performLoadMnemonicState = loadMnemonicState
            self.performDeleteMnemonic = deleteMnemonic
            self.isLoadFailureRecoverable = recoverableLoadFailure
        }

        public func saveMnemonic(
            _ mnemonic: OpalBase.Storage.StoredMnemonic,
            generation: String,
            fallbackToPlaintext: Bool
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            try await saveMnemonic(
                mnemonic,
                generation: generation,
                policy: fallbackToPlaintext ? .legacyFallbackToPlaintext : .acceptProviderOutput
            )
        }

        public func saveMnemonic(
            _ mnemonic: OpalBase.Storage.StoredMnemonic,
            generation: String,
            policy: OpalBase.Storage.Security.PersistencePolicy
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            try await performSaveMnemonic(mnemonic, generation, policy)
        }

        public func loadMnemonicState(generation: String) async throws -> (
            mnemonic: OpalBase.Storage.StoredMnemonic,
            protectionMode: OpalBase.Storage.Security.ProtectionMode
        )? {
            try await performLoadMnemonicState(generation)
        }

        public func deleteMnemonic(generation: String) async throws {
            try await performDeleteMnemonic(generation)
        }

        func isRecoverableLoadFailure(_ error: Swift.Error) -> Bool {
            isLoadFailureRecoverable(error)
        }

        private static func makePolicyEnforcingSave(
            _ saveMnemonicWithPolicy: @escaping @Sendable (
                OpalBase.Storage.StoredMnemonic,
                String,
                OpalBase.Storage.Security.PersistencePolicy
            ) async throws -> OpalBase.Storage.Security.ProtectionMode,
            deleteMnemonic: @escaping @Sendable (String) async throws -> Void
        ) -> @Sendable (
            OpalBase.Storage.StoredMnemonic,
            String,
            OpalBase.Storage.Security.PersistencePolicy
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            { mnemonic, generation, policy in
                let protectionMode = try await saveMnemonicWithPolicy(mnemonic, generation, policy)
                if policy == .requireSecureEnclave, protectionMode != .secureEnclave {
                    try? await deleteMnemonic(generation)
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
        return StoredMnemonicPersistence(
            saveMnemonicWithPolicy: saveMnemonic(_:generation:policy:),
            loadMnemonicState: loadMnemonicState(generation:),
            deleteMnemonic: deleteMnemonic(generation:),
            recoverableLoadFailure: isRecoverableStoredMnemonicLoadFailure
        )
    }
}
