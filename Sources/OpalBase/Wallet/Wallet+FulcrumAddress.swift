// Wallet+FulcrumAddress.swift

import Foundation

extension Wallet {
    public actor FulcrumAddress {
        private let addressReader: Network.AddressReadable
        private let transactionHandler: Network.TransactionConfirming
        
        public init(addressReader: Network.AddressReadable,
                    transactionHandler: Network.TransactionConfirming) {
            self.addressReader = addressReader
            self.transactionHandler = transactionHandler
        }
        
        public func refreshBalances(for account: Account,
                                    usage: DerivationPath.Usage? = nil,
                                    includeUnconfirmedHistory: Bool = true) async throws -> Account.BalanceRefresh {
            _ = try await account.scanForUsedAddresses(using: addressReader,
                                                       usage: usage,
                                                       includeUnconfirmed: includeUnconfirmedHistory)
            return try await account.refreshBalances(for: usage) { address in
                let balance = try await self.addressReader.fetchBalance(for: address.string, tokenFilter: .include)
                return try Self.makeBalance(from: balance)
            }
        }
        
        public func refreshBalances(forAccountAt unhardenedIndex: UInt32,
                                    in wallet: Wallet,
                                    usage: DerivationPath.Usage? = nil,
                                    includeUnconfirmedHistory: Bool = true) async throws -> Account.BalanceRefresh {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await refreshBalances(for: account,
                                             usage: usage,
                                             includeUnconfirmedHistory: includeUnconfirmedHistory)
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
        
        public func makeMonitor(for account: Account,
                                blockHeaderReader: Network.BlockHeaderReadable,
                                includeUnconfirmed: Bool = true,
                                retryDelay: Duration = .seconds(2)) -> Monitor {
            Monitor(account: account,
                    addressReader: addressReader,
                    blockHeaderReader: blockHeaderReader,
                    transactionHandler: transactionHandler,
                    includeUnconfirmed: includeUnconfirmed,
                    retryDelay: retryDelay)
        }
        
        public func makeMonitor(forAccountAt unhardenedIndex: UInt32,
                                in wallet: Wallet,
                                blockHeaderReader: Network.BlockHeaderReadable,
                                includeUnconfirmed: Bool = true,
                                retryDelay: Duration = .seconds(2)) async throws -> Monitor {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return makeMonitor(for: account,
                               blockHeaderReader: blockHeaderReader,
                               includeUnconfirmed: includeUnconfirmed,
                               retryDelay: retryDelay)
        }
        
        public func makeEventStream(for account: Account,
                                    blockHeaderReader: Network.BlockHeaderReadable,
                                    includeUnconfirmed: Bool = true,
                                    retryDelay: Duration = .seconds(2)) async -> AsyncThrowingStream<Monitor.Event, Swift.Error> {
            let monitor = makeMonitor(for: account,
                                      blockHeaderReader: blockHeaderReader,
                                      includeUnconfirmed: includeUnconfirmed,
                                      retryDelay: retryDelay)
            return await monitor.makeEventStream()
        }
        
        public func makeEventStream(forAccountAt unhardenedIndex: UInt32,
                                    in wallet: Wallet,
                                    blockHeaderReader: Network.BlockHeaderReadable,
                                    includeUnconfirmed: Bool = true,
                                    retryDelay: Duration = .seconds(2)) async throws -> AsyncThrowingStream<Monitor.Event, Swift.Error> {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return await makeEventStream(for: account,
                                         blockHeaderReader: blockHeaderReader,
                                         includeUnconfirmed: includeUnconfirmed,
                                         retryDelay: retryDelay)
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
        
        let confirmed = try Satoshi(balance.confirmed)
        return try confirmed + Satoshi(positiveUnconfirmed)
    }
}
