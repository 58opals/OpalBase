// OpalBase+WalletSecretAccessInteractor.swift

public extension OpalBase {
    /// Secret-loading and wipe lane for mnemonic, Keychain, Secure Enclave, migration, and recovery flows.
    struct WalletSecretAccessInteractor: Sendable {
        private let persistenceSession: OpalBase.Storage.PersistenceSession

        public init(persistenceSession: OpalBase.Storage.PersistenceSession) {
            self.persistenceSession = persistenceSession
        }

        public init(storage: OpalBase.Storage) async {
            self.init(persistenceSession: await OpalBase.Storage.PersistenceSession(storage: storage))
        }

        @discardableResult
        public func saveWalletSecretsAndSnapshot(
            from wallet: OpalBase.Wallet,
            policy: OpalBase.Storage.Security.PersistencePolicy
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            try await persistenceSession.save(wallet: wallet, policy: policy)
        }

        @discardableResult
        public func saveWalletSecretsAndSnapshot(
            from wallet: OpalBase.Wallet,
            profile: OpalBase.WalletSecurityProfile
        ) async throws -> OpalBase.Storage.Security.ProtectionMode {
            try await saveWalletSecretsAndSnapshot(
                from: wallet,
                policy: profile.secretPersistencePolicy
            )
        }

        public func restoreWalletSecretsAndSnapshot() async throws -> OpalBase.Storage.PersistenceSession.RestoredState {
            try await persistenceSession.restore()
        }

        public func wipeWalletSecretsAndSnapshots() async throws {
            try await persistenceSession.wipe()
        }
    }
}
