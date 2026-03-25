// OpalBase+Storage+StoredMnemonicStore.swift

import Foundation

extension _OpalBase.Storage {
    public struct StoredMnemonicStore: Sendable {
        private let saveMnemonicHandler: @Sendable (
            OpalBase.Storage.StoredMnemonic,
            String,
            OpalBase.Storage.Security.PersistencePolicy
        ) async throws -> OpalBase.Storage.Security.ProtectionMode
        private let loadMnemonicStateHandler: @Sendable (String) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?
        private let deleteMnemonicHandler: @Sendable (String) async throws -> Void

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
    }

    public nonisolated func makeStoredMnemonicStore() -> StoredMnemonicStore {
        StoredMnemonicStore(
            saveMnemonicWithPolicy: saveMnemonic(_:generation:policy:),
            loadMnemonicState: loadMnemonicState(generation:),
            deleteMnemonic: deleteMnemonic(generation:)
        )
    }
}
