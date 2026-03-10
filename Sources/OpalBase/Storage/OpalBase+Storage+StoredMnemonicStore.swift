// OpalBase+Storage+StoredMnemonicStore.swift

import Foundation

extension _OpalBase.Storage {
    public struct StoredMnemonicStore: Sendable {
        private let saveMnemonicHandler: @Sendable (OpalBase.Storage.StoredMnemonic, String, Bool) async throws -> OpalBase.Storage.Security.ProtectionMode
        private let loadMnemonicStateHandler: @Sendable (String) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?
        private let deleteMnemonicHandler: @Sendable (String) async throws -> Void

        public init(
            saveMnemonic: @escaping @Sendable (OpalBase.Storage.StoredMnemonic, String, Bool) async throws -> OpalBase.Storage.Security.ProtectionMode,
            loadMnemonicState: @escaping @Sendable (String) async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?,
            deleteMnemonic: @escaping @Sendable (String) async throws -> Void
        ) {
            self.saveMnemonicHandler = saveMnemonic
            self.loadMnemonicStateHandler = loadMnemonicState
            self.deleteMnemonicHandler = deleteMnemonic
        }

        public func saveMnemonic(
            _ mnemonic: OpalBase.Storage.StoredMnemonic,
            generation: String,
            fallbackToPlaintext: Bool
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            try await saveMnemonicHandler(mnemonic, generation, fallbackToPlaintext)
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
            saveMnemonic: saveMnemonic(_:generation:fallbackToPlaintext:),
            loadMnemonicState: loadMnemonicState(generation:),
            deleteMnemonic: deleteMnemonic(generation:)
        )
    }
}
