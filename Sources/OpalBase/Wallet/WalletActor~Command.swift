// WalletActor~Command.swift

import Foundation

extension WalletActor {
    public func prepareSpend(forAccountAt unhardenedIndex: UInt32,
                             payment: AccountActor.PaymentModel,
                             feePolicy: FeePolicy = .init()) async throws -> AccountActor.SpendPlanModel {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.prepareSpend(payment, feePolicy: feePolicy)
        }
    }
    
    public func prepareTokenSpend(forAccountAt unhardenedIndex: UInt32,
                                  transfer: AccountActor.TokenTransferModel,
                                  feePolicy: FeePolicy = .init()) async throws -> AccountActor.TokenSpendPlanModel {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.prepareTokenSpend(transfer, feePolicy: feePolicy)
        }
    }
    
    public func prepareTokenGenesis(forAccountAt index: UInt32,
                                    genesis: AccountActor.TokenGenesisModel,
                                    feePolicy: FeePolicy = .init()) async throws -> AccountActor.TokenGenesisPlanModel {
        try await performWithAccount(at: index) { account in
            try await account.prepareTokenGenesis(genesis, feePolicy: feePolicy)
        }
    }
    
    public func prepareTokenGenesisOutpoint(forAccountAt index: UInt32,
                                            feePolicy: FeePolicy = .init()) async throws -> AccountActor.SpendPlanModel {
        try await performWithAccount(at: index) { account in
            try await account.prepareTokenGenesisOutpoint(feePolicy: feePolicy)
        }
    }
    
    public func prepareTokenMint(
        forAccountAt unhardenedIndex: UInt32,
        mint: AccountActor.TokenMintModel,
        preferredMintingInput: TransactionModel.OutputModel.UnspentModel? = nil,
        feePolicy: FeePolicy = .init()
    ) async throws -> AccountActor.TokenMintPlanModel {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.prepareTokenMint(mint,
                                               preferredMintingInput: preferredMintingInput,
                                               feePolicy: feePolicy)
        }
    }
    
    public func prepareTokenCommitmentMutation(
        forAccountAt unhardenedIndex: UInt32,
        mutation: AccountActor.TokenCommitmentMutationModel,
        feePolicy: FeePolicy = .init()
    ) async throws -> AccountActor.TokenCommitmentMutationPlanModel {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.prepareTokenCommitmentMutation(mutation, feePolicy: feePolicy)
        }
    }
    
    public func refreshBalances(forAccountAt unhardenedIndex: UInt32,
                                usage: DerivationPathModel.UsageModel? = nil,
                                loader: @escaping @Sendable (AddressModel) async throws -> SatoshiModel) async throws -> AccountActor.BalanceRefreshModel {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.refreshBalances(for: usage, loader: loader)
        }
    }
    
    public func refreshTransactionHistory(forAccountAt unhardenedIndex: UInt32,
                                          usage: DerivationPathModel.UsageModel? = nil,
                                          includeUnconfirmed: Bool = true,
                                          using service: NetworkModel.AddressReadable,
                                          transactionReader: NetworkModel.TransactionReadableClient? = nil) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.refreshTransactionHistory(using: service,
                                                        usage: usage,
                                                        includeUnconfirmed: includeUnconfirmed,
                                                        transactionReader: transactionReader)
        }
    }
    
    public func updateTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                               transactionHashes: [TransactionModel.HashModel],
                                               using handler: NetworkModel.TransactionConfirmationClient) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.updateTransactionConfirmations(using: handler,
                                                             for: transactionHashes)
        }
    }
    
    public func refreshTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                                using handler: NetworkModel.TransactionConfirmationClient) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.refreshTransactionConfirmations(using: handler)
        }
    }
}

private extension WalletActor {
    func performWithAccount<T>(at unhardenedIndex: UInt32,
                               _ work: (AccountActor) async throws -> T) async throws -> T {
        let account = try await fetchAccount(at: unhardenedIndex)
        return try await work(account)
    }
}
