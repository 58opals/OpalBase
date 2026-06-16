// OpalBase+WalletManagementInteractor.swift

public extension OpalBase {
    /// Wallet management lane for account creation, restore composition, and account discovery.
    struct WalletManagementInteractor: Sendable {
        private let wallet: OpalBase.Wallet

        public init(wallet: OpalBase.Wallet) {
            self.wallet = wallet
        }

        public func addAccount(unhardenedIndex: UInt32) async throws {
            try await wallet.addAccount(unhardenedIndex: unhardenedIndex)
        }

        public func fetchAccount(at unhardenedIndex: UInt32) async throws -> OpalBase.Account {
            try await wallet.fetchAccount(at: unhardenedIndex)
        }

        public func numberOfAccounts() async -> Int {
            await wallet.numberOfAccounts
        }

        public func makeSnapshot() async -> OpalBase.Wallet.Snapshot {
            await wallet.makeSnapshot()
        }
    }
}
