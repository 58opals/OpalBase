// Wallet~Command.swift

import Foundation

extension Wallet {
    public func prepareSpend(forAccountAt unhardenedIndex: UInt32,
                             payment: Account.Payment,
                             feePolicy: FeePolicy = .init()) async throws -> Account.SpendPlan {
        let account = try await fetchAccount(at: unhardenedIndex)
        return try await account.prepareSpend(payment, feePolicy: feePolicy)
    }
    
    public func refreshBalances(forAccountAt unhardenedIndex: UInt32,
                                usage: DerivationPath.Usage? = nil,
                                loader: @escaping @Sendable (Address) async throws -> Satoshi) async throws -> Account.BalanceRefresh {
        let account = try await fetchAccount(at: unhardenedIndex)
        return try await account.refreshBalances(for: usage, loader: loader)
    }
}
