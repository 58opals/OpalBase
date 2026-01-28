// Wallet~Command.swift

import Foundation

extension Wallet {
    public func prepareSpend(forAccountAt unhardenedIndex: UInt32,
                             payment: Account.Payment,
                             feePolicy: FeePolicy = .init()) async throws -> Account.SpendPlan {
        let account = try await fetchAccount(at: unhardenedIndex)
        return try await account.prepareSpend(payment, feePolicy: feePolicy)
    }
    
    public func prepareTokenSpend(forAccountAt unhardenedIndex: UInt32,
                                  transfer: Account.TokenTransfer,
                                  feePolicy: FeePolicy = .init()) async throws -> Account.TokenSpendPlan {
        let account = try await fetchAccount(at: unhardenedIndex)
        return try await account.prepareTokenSpend(transfer, feePolicy: feePolicy)
    }
    
    public func prepareTokenGenesis(forAccountAt index: UInt32,
                                    genesis: Account.TokenGenesis,
                                    feePolicy: FeePolicy = .init()) async throws -> Account.TokenGenesisPlan {
        let account = try await fetchAccount(at: index)
        return try await account.prepareTokenGenesis(genesis, feePolicy: feePolicy)
    }
    
    public func prepareTokenGenesisOutpoint(forAccountAt index: UInt32,
                                            feePolicy: FeePolicy = .init()) async throws -> Account.SpendPlan {
        let account = try await fetchAccount(at: index)
        return try await account.prepareTokenGenesisOutpoint(feePolicy: feePolicy)
    }
    
    public func prepareTokenMint(
        forAccountAt unhardenedIndex: UInt32,
        mint: Account.TokenMint,
        preferredMintingInput: Transaction.Output.Unspent? = nil,
        feePolicy: FeePolicy = .init()
    ) async throws -> Account.TokenMintPlan {
        let account = try await fetchAccount(at: unhardenedIndex)
        return try await account.prepareTokenMint(mint,
                                                  preferredMintingInput: preferredMintingInput,
                                                  feePolicy: feePolicy)
    }
    
    public func refreshBalances(forAccountAt unhardenedIndex: UInt32,
                                usage: DerivationPath.Usage? = nil,
                                loader: @escaping @Sendable (Address) async throws -> Satoshi) async throws -> Account.BalanceRefresh {
        let account = try await fetchAccount(at: unhardenedIndex)
        return try await account.refreshBalances(for: usage, loader: loader)
    }
    
    public func refreshTransactionHistory(forAccountAt unhardenedIndex: UInt32,
                                          usage: DerivationPath.Usage? = nil,
                                          includeUnconfirmed: Bool = true,
                                          using service: Network.AddressReadable,
                                          transactionReader: Network.TransactionReadable? = nil) async throws -> Transaction.History.ChangeSet {
        let account = try await fetchAccount(at: unhardenedIndex)
        return try await account.refreshTransactionHistory(using: service,
                                                           usage: usage,
                                                           includeUnconfirmed: includeUnconfirmed,
                                                           transactionReader: transactionReader)
    }
    
    public func updateTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                               transactionHashes: [Transaction.Hash],
                                               using handler: Network.TransactionConfirming) async throws -> Transaction.History.ChangeSet {
        let account = try await fetchAccount(at: unhardenedIndex)
        return try await account.updateTransactionConfirmations(using: handler,
                                                                for: transactionHashes)
    }
    
    public func refreshTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                                using handler: Network.TransactionConfirming) async throws -> Transaction.History.ChangeSet {
        let account = try await fetchAccount(at: unhardenedIndex)
        return try await account.refreshTransactionConfirmations(using: handler)
    }
}
