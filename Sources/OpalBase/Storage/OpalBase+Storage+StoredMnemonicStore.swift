// OpalBase+Storage+StoredMnemonicStore.swift

import Foundation

extension _OpalBase.Storage {
    public struct StoredMnemonicStore: Sendable {
        private let saveMnemonicHandler: @Sendable (OpalBase.Storage.StoredMnemonic, Bool) async throws -> OpalBase.Storage.Security.ProtectionMode
        private let loadMnemonicStateHandler: @Sendable () async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?

        public init(
            saveMnemonic: @escaping @Sendable (OpalBase.Storage.StoredMnemonic, Bool) async throws -> OpalBase.Storage.Security.ProtectionMode,
            loadMnemonicState: @escaping @Sendable () async throws -> (mnemonic: OpalBase.Storage.StoredMnemonic, protectionMode: OpalBase.Storage.Security.ProtectionMode)?
        ) {
            self.saveMnemonicHandler = saveMnemonic
            self.loadMnemonicStateHandler = loadMnemonicState
        }

        public func saveMnemonic(
            _ mnemonic: OpalBase.Storage.StoredMnemonic,
            fallbackToPlaintext: Bool
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            try await saveMnemonicHandler(mnemonic, fallbackToPlaintext)
        }

        public func loadMnemonicState() async throws -> (
            mnemonic: OpalBase.Storage.StoredMnemonic,
            protectionMode: OpalBase.Storage.Security.ProtectionMode
        )? {
            try await loadMnemonicStateHandler()
        }
    }

    public nonisolated func makeStoredMnemonicStore() -> StoredMnemonicStore {
        StoredMnemonicStore(
            saveMnemonic: saveMnemonic(_:fallbackToPlaintext:),
            loadMnemonicState: loadMnemonicState
        )
    }
}
