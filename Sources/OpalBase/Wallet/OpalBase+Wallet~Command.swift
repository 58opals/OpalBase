// OpalBase+Wallet~Command.swift

import Foundation

extension _OpalBase.Wallet {
    public func prepareSpend(forAccountAt unhardenedIndex: UInt32,
                             payment: OpalBase.Account.Payment,
                             feePolicy: FeePolicy = .init()) async throws -> OpalBase.Account.SpendPlan {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.prepareSpend(payment, feePolicy: feePolicy)
        }
    }
    
    public func prepareTokenSpend(forAccountAt unhardenedIndex: UInt32,
                                  transfer: OpalBase.Account.TokenTransfer,
                                  feePolicy: FeePolicy = .init()) async throws -> OpalBase.Account.TokenSpendPlan {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.prepareTokenSpend(transfer, feePolicy: feePolicy)
        }
    }
    
    public func prepareTokenGenesis(forAccountAt index: UInt32,
                                    genesis: OpalBase.Account.TokenGenesis,
                                    feePolicy: FeePolicy = .init()) async throws -> OpalBase.Account.TokenGenesisPlan {
        try await performWithAccount(at: index) { account in
            try await account.prepareTokenGenesis(genesis, feePolicy: feePolicy)
        }
    }
    
    public func prepareTokenGenesisOutpoint(forAccountAt index: UInt32,
                                            feePolicy: FeePolicy = .init()) async throws -> OpalBase.Account.SpendPlan {
        try await performWithAccount(at: index) { account in
            try await account.prepareTokenGenesisOutpoint(feePolicy: feePolicy)
        }
    }
    
    public func prepareTokenMint(
        forAccountAt unhardenedIndex: UInt32,
        mint: OpalBase.Account.TokenMint,
        preferredMintingInput: OpalBase.Transaction.OutputModel.Unspent? = nil,
        feePolicy: FeePolicy = .init()
    ) async throws -> OpalBase.Account.TokenMintPlan {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.prepareTokenMint(mint,
                                               preferredMintingInput: preferredMintingInput,
                                               feePolicy: feePolicy)
        }
    }
    
    public func prepareTokenCommitmentMutation(
        forAccountAt unhardenedIndex: UInt32,
        mutation: OpalBase.Account.TokenCommitmentMutation,
        feePolicy: FeePolicy = .init()
    ) async throws -> OpalBase.Account.TokenCommitmentMutationPlan {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.prepareTokenCommitmentMutation(mutation, feePolicy: feePolicy)
        }
    }
    
    public func refreshBalances(forAccountAt unhardenedIndex: UInt32,
                                usage: OpalBase.DerivationPath.UsageModel? = nil,
                                loader: @escaping @Sendable (OpalBase.Address) async throws -> OpalBase.Satoshi) async throws -> OpalBase.Account.BalanceRefresh {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.refreshBalances(for: usage, loader: loader)
        }
    }
    
    public func refreshTransactionHistory(forAccountAt unhardenedIndex: UInt32,
                                          usage: OpalBase.DerivationPath.UsageModel? = nil,
                                          includeUnconfirmed: Bool = true,
                                          using service: OpalBase.Network.AddressReadable,
                                          transactionReader: OpalBase.Network.TransactionReadableClient? = nil) async throws -> OpalBase.Transaction.HistoryModel.ChangeSet {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.refreshTransactionHistory(using: service,
                                                        usage: usage,
                                                        includeUnconfirmed: includeUnconfirmed,
                                                        transactionReader: transactionReader)
        }
    }
    
    public func updateTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                               transactionHashes: [OpalBase.Transaction.HashModel],
                                               using handler: OpalBase.Network.TransactionConfirmationClient) async throws -> OpalBase.Transaction.HistoryModel.ChangeSet {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.updateTransactionConfirmations(using: handler,
                                                             for: transactionHashes)
        }
    }
    
    public func refreshTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                                using handler: OpalBase.Network.TransactionConfirmationClient) async throws -> OpalBase.Transaction.HistoryModel.ChangeSet {
        try await performWithAccount(at: unhardenedIndex) { account in
            try await account.refreshTransactionConfirmations(using: handler)
        }
    }
}

private extension _OpalBase.Wallet {
    func performWithAccount<T>(at unhardenedIndex: UInt32,
                               _ work: (OpalBase.Account) async throws -> T) async throws -> T {
        let account = try await fetchAccount(at: unhardenedIndex)
        return try await work(account)
    }
}
