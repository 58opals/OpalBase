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
    
    public func refreshBalances(forAccountAt unhardenedIndex: UInt32,
                                usage: DerivationPath.Usage? = nil,
                                loader: @escaping @Sendable (Address) async throws -> Satoshi) async throws -> Account.BalanceRefresh {
        let account = try await fetchAccount(at: unhardenedIndex)
        return try await account.refreshBalances(for: usage, loader: loader)
    }
    
    public func refreshTransactionHistory(forAccountAt unhardenedIndex: UInt32,
                                          usage: DerivationPath.Usage? = nil,
                                          includeUnconfirmed: Bool = true,
                                          using service: Network.AddressReadable) async throws -> Transaction.History.ChangeSet {
        let account = try await fetchAccount(at: unhardenedIndex)
        return try await account.refreshTransactionHistory(using: service,
                                                           usage: usage,
                                                           includeUnconfirmed: includeUnconfirmed)
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
