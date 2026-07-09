// OpalBase+WalletBlockchainSyncInteractor.swift

public extension OpalBase {
    /// Descriptor-backed public-chain sync lane for balances, history, UTXOs, and confirmation freshness.
    struct WalletBlockchainSyncInteractor: Sendable {
        private let account: OpalBase.Account
        private let publicChain: OpalBase.WalletPublicChainOperations

        public init(
            accountDescriptor: OpalBase.WalletAccountPublicDescriptor,
            publicChain: OpalBase.WalletPublicChainOperations
        ) async throws {
            self.account = try await accountDescriptor.makeReadOnlyAccount()
            self.publicChain = publicChain
        }

        public init(
            readOnlyAccount: OpalBase.Account,
            publicChain: OpalBase.WalletPublicChainOperations
        ) {
            self.account = readOnlyAccount
            self.publicChain = publicChain
        }

        public func refreshBalances(
            usage: OpalBase.Key.DerivationPath.Usage? = nil,
            includeUnconfirmedHistory: Bool = true
        ) async throws -> OpalBase.Account.BalanceRefresh {
            _ = try await account.scanForUsedAddresses(
                using: publicChain.addressReader,
                usage: usage,
                includeUnconfirmed: includeUnconfirmedHistory
            )
            return try await account.refreshBalances(for: usage) { address in
                let balance = try await publicChain.addressReader.fetchBalance(
                    for: address.string,
                    tokenFilter: .include
                )
                return try balance.confirmedPlusUnconfirmedSatoshi()
            }
        }

        public func refreshUTXOSet(
            usage: OpalBase.Key.DerivationPath.Usage? = nil
        ) async throws -> OpalBase.Account.UTXORefresh {
            try await account.refreshUTXOSet(using: publicChain.addressReader, usage: usage)
        }

        public func refreshTransactionHistory(
            usage: OpalBase.Key.DerivationPath.Usage? = nil,
            includeUnconfirmed: Bool = true
        ) async throws -> OpalBase.Transaction.History.ChangeSet {
            try await account.refreshTransactionHistory(
                using: publicChain.addressReader,
                usage: usage,
                includeUnconfirmed: includeUnconfirmed,
                transactionReader: publicChain.transactionReader
            )
        }

        public func updateTransactionConfirmations(
            for transactionHashes: [OpalBase.Transaction.Hash]
        ) async throws -> OpalBase.Transaction.History.ChangeSet {
            try await account.updateTransactionConfirmations(
                using: publicChain.transactionClient,
                for: transactionHashes
            )
        }

        public func refreshTransactionConfirmations() async throws -> OpalBase.Transaction.History.ChangeSet {
            try await account.refreshTransactionConfirmations(using: publicChain.transactionClient)
        }

        public func makeSnapshot() async -> OpalBase.Account.Snapshot {
            await account.makeSnapshot()
        }
    }
}
