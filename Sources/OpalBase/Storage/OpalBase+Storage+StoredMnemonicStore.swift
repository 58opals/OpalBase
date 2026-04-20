// OpalBase+Storage+StoredMnemonicStore.swift

import Foundation

private func isRecoverableStoredMnemonicLoadFailure(
    _ error: Swift.Error
) -> Bool {
    if let storageError = error as? OpalBase.Storage.Error {
        switch storageError {
        case .secureStoreFailure(let underlying):
            return isRecoverableStoredMnemonicLoadFailure(underlying)
        default:
            return false
        }
    }

    if let securityError = error as? OpalBase.Storage.Security.Error {
        switch securityError {
        case .decryptionFailure(let underlying):
            return isRecoverableStoredMnemonicLoadFailure(underlying)
        case .protectionUnavailable, .insufficientProtection, .encryptionFailure:
            return false
        }
    }

    let nsError = error as NSError
    return nsError.domain == NSOSStatusErrorDomain
        && nsError.code == Int(errSecItemNotFound)
}

extension _OpalBase.Storage {
    public struct StoredMnemonicStore: Sendable {
        private let saveMnemonicHandler: @Sendable (
            OpalBase.Storage.StoredMnemonic,
            String,
            OpalBase.Storage.Security.PersistencePolicy
        ) async throws -> OpalBase.Storage.Security.ProtectionMode
        private let loadMnemonicStateHandler: @Sendable (String) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?
        private let deleteMnemonicHandler: @Sendable (String) async throws -> Void
        private let recoverableLoadFailureHandler: @Sendable (Swift.Error) -> Bool

        public init(
            saveMnemonic: @escaping @Sendable (OpalBase.Storage.StoredMnemonic, String, Bool) async throws -> OpalBase.Storage.Security.ProtectionMode,
            loadMnemonicState: @escaping @Sendable (String) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?,
            deleteMnemonic: @escaping @Sendable (String) async throws -> Void
        ) {
            self.saveMnemonicHandler = { mnemonic, generation, policy in
                let protectionMode = try await saveMnemonic(
                    mnemonic,
                    generation,
                    policy == .legacyFallbackToPlaintext
                )
                if policy == .requireSecureEnclave, protectionMode != .secureEnclave {
                    throw OpalBase.Storage.Security.Error.insufficientProtection(
                        required: .secureEnclave,
                        actual: protectionMode
                    )
                }
                return protectionMode
            }
            self.loadMnemonicStateHandler = loadMnemonicState
            self.deleteMnemonicHandler = deleteMnemonic
            self.recoverableLoadFailureHandler = { _ in false }
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
            self.saveMnemonicHandler = saveMnemonicWithPolicy
            self.loadMnemonicStateHandler = loadMnemonicState
            self.deleteMnemonicHandler = deleteMnemonic
            self.recoverableLoadFailureHandler = { _ in false }
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
            self.saveMnemonicHandler = saveMnemonicWithPolicy
            self.loadMnemonicStateHandler = loadMnemonicState
            self.deleteMnemonicHandler = deleteMnemonic
            self.recoverableLoadFailureHandler = recoverableLoadFailure
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
            try await saveMnemonicHandler(mnemonic, generation, policy)
        }

        public func loadMnemonicState(generation: String) async throws -> (
            mnemonic: OpalBase.Storage.StoredMnemonic,
            protectionMode: OpalBase.Storage.Security.ProtectionMode
        )? {
            try await loadMnemonicStateHandler(generation)
        }

        public func deleteMnemonic(generation: String) async throws {
            try await deleteMnemonicHandler(generation)
        }

        func isRecoverableLoadFailure(_ error: Swift.Error) -> Bool {
            recoverableLoadFailureHandler(error)
        }
    }

    public func makeStoredMnemonicStore() -> StoredMnemonicStore {
        let recoverableLoadFailure: @Sendable (Swift.Error) -> Bool = { error in
            isRecoverableStoredMnemonicLoadFailure(error)
        }

        return StoredMnemonicStore(
            saveMnemonicWithPolicy: saveMnemonic(_:generation:policy:),
            loadMnemonicState: loadMnemonicState(generation:),
            deleteMnemonic: deleteMnemonic(generation:),
            recoverableLoadFailure: recoverableLoadFailure
        )
    }
}
