// OpalBase+WalletAssetInteractor.swift

public extension OpalBase {
    /// Asset lane for token holdings and token metadata. Mint authoring stays explicit through `privateAccount`.
    struct WalletAssetInteractor: Sendable {
        private let account: OpalBase.Account
        private let metadataWallet: OpalBase.Wallet?
        private let privateAccount: OpalBase.Account?
        private let feePolicy: OpalBase.Wallet.FeePolicy

        public init(
            account: OpalBase.Account,
            metadataWallet: OpalBase.Wallet? = nil
        ) {
            self.account = account
            self.metadataWallet = metadataWallet
            self.privateAccount = nil
            self.feePolicy = .init()
        }

        public init(
            privateAccount: OpalBase.Account,
            metadataWallet: OpalBase.Wallet? = nil,
            feePolicy: OpalBase.Wallet.FeePolicy = .init()
        ) {
            self.account = privateAccount
            self.metadataWallet = metadataWallet
            self.privateAccount = privateAccount
            self.feePolicy = feePolicy
        }

        public func loadTokenInventory() async throws -> OpalBase.Account.TokenInventory {
            try await account.loadTokenInventory()
        }

        public func fetchTokenMetadata(
            for category: OpalBase.CashTokens.CategoryID
        ) async -> OpalBase.CashTokens.Metadata? {
            await metadataWallet?.fetchTokenMetadata(for: category)
        }

        public func upsertTokenMetadata(
            _ items: [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata]
        ) async {
            await metadataWallet?.upsertTokenMetadata(items)
        }

        public func makeTokenMetadataSnapshot() async -> OpalBase.CashTokens.MetadataRepository.Snapshot? {
            await metadataWallet?.makeTokenMetadataSnapshot()
        }

        public func prepareTokenMint(
            _ mint: OpalBase.Account.TokenMint,
            preferredMintingInput: OpalBase.Transaction.Output.Unspent? = nil
        ) async throws -> OpalBase.Account.TokenMintPlan {
            guard let privateAccount else {
                throw OpalBase.Account.Error.privateKeyMaterialUnavailable
            }
            return try await privateAccount.prepareTokenMint(
                mint,
                preferredMintingInput: preferredMintingInput,
                feePolicy: feePolicy
            )
        }
    }
}
