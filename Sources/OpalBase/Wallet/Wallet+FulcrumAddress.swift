// Wallet+FulcrumAddress.swift

import Foundation

extension Wallet {
    public actor FulcrumAddress {
        private let addressReader: Network.FulcrumAddressReader
        private let transactionHandler: Network.FulcrumTransactionHandler
        
        public init(addressReader: Network.FulcrumAddressReader,
                    transactionHandler: Network.FulcrumTransactionHandler) {
            self.addressReader = addressReader
            self.transactionHandler = transactionHandler
        }
        
        public func refreshBalances(for account: Account,
                                    usage: DerivationPath.Usage? = nil) async throws -> Account.BalanceRefresh {
            try await account.refreshBalances(for: usage) { address in
                let balance = try await self.addressReader.fetchBalance(for: address.string)
                return try Self.makeBalance(from: balance)
            }
        }
        
        public func refreshBalances(forAccountAt unhardenedIndex: UInt32,
                                    in wallet: Wallet,
                                    usage: DerivationPath.Usage? = nil) async throws -> Account.BalanceRefresh {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await refreshBalances(for: account, usage: usage)
        }
        
        public func refreshTransactionHistory(for account: Account,
                                              usage: DerivationPath.Usage? = nil,
                                              includeUnconfirmed: Bool = true) async throws -> Transaction.History.ChangeSet {
            try await account.refreshTransactionHistory(using: addressReader,
                                                        usage: usage,
                                                        includeUnconfirmed: includeUnconfirmed)
        }
        
        public func refreshTransactionHistory(forAccountAt unhardenedIndex: UInt32,
                                              in wallet: Wallet,
                                              usage: DerivationPath.Usage? = nil,
                                              includeUnconfirmed: Bool = true) async throws -> Transaction.History.ChangeSet {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await refreshTransactionHistory(for: account,
                                                       usage: usage,
                                                       includeUnconfirmed: includeUnconfirmed)
        }
        
        public func updateTransactionConfirmations(for account: Account,
                                                   transactionHashes: [Transaction.Hash]) async throws -> Transaction.History.ChangeSet {
            try await account.updateTransactionConfirmations(using: transactionHandler,
                                                             for: transactionHashes)
        }
        
        public func updateTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                                   in wallet: Wallet,
                                                   transactionHashes: [Transaction.Hash]) async throws -> Transaction.History.ChangeSet {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await updateTransactionConfirmations(for: account,
                                                            transactionHashes: transactionHashes)
        }
        
        public func refreshTransactionConfirmations(for account: Account) async throws -> Transaction.History.ChangeSet {
            try await account.refreshTransactionConfirmations(using: transactionHandler)
        }
        
        public func refreshTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                                    in wallet: Wallet) async throws -> Transaction.History.ChangeSet {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await refreshTransactionConfirmations(for: account)
        }
    }
}

private extension Wallet.FulcrumAddress {
    static func makeBalance(from balance: Network.AddressBalance) throws -> Satoshi {
        let positiveUnconfirmed: UInt64
        if balance.unconfirmed > 0 {
            guard let value = UInt64(exactly: balance.unconfirmed) else {
                throw Satoshi.Error.exceedsMaximumAmount
            }
            positiveUnconfirmed = value
        } else {
            positiveUnconfirmed = 0
        }
        
        let (sum, overflow) = balance.confirmed.addingReportingOverflow(positiveUnconfirmed)
        if overflow {
            throw Satoshi.Error.exceedsMaximumAmount
        }
        return try Satoshi(sum)
    }
}
