// OpalBase+Wallet+Fulcrum.swift

import Foundation

extension _OpalBase.Wallet {
    public actor Fulcrum {
        private let addressReader: OpalBase.Network.AddressReadable
        private let transactionHandler: OpalBase.Network.TransactionConfirmationClient
        private let transactionReader: OpalBase.Network.TransactionReadableClient?
        
        public init(addressReader: OpalBase.Network.AddressReadable,
                    transactionHandler: OpalBase.Network.TransactionConfirmationClient,
                    transactionReader: OpalBase.Network.TransactionReadableClient? = nil) {
            self.addressReader = addressReader
            self.transactionHandler = transactionHandler
            self.transactionReader = transactionReader
        }
        
        public func refreshBalances(for account: OpalBase.Account,
                                    usage: OpalBase.DerivationPath.UsageModel? = nil,
                                    includeUnconfirmedHistory: Bool = true) async throws -> OpalBase.Account.BalanceRefresh {
            _ = try await account.scanForUsedAddresses(using: addressReader,
                                                       usage: usage,
                                                       includeUnconfirmed: includeUnconfirmedHistory)
            return try await account.refreshBalances(for: usage) { address in
                let balance = try await self.addressReader.fetchBalance(for: address.string, tokenFilter: .include)
                return try Self.makeBalance(from: balance)
            }
        }
        
        public func refreshBalances(forAccountAt unhardenedIndex: UInt32,
                                    in wallet: OpalBase.Wallet,
                                    usage: OpalBase.DerivationPath.UsageModel? = nil,
                                    includeUnconfirmedHistory: Bool = true) async throws -> OpalBase.Account.BalanceRefresh {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await refreshBalances(for: account,
                                             usage: usage,
                                             includeUnconfirmedHistory: includeUnconfirmedHistory)
        }
        
        public func refreshTransactionHistory(for account: OpalBase.Account,
                                              usage: OpalBase.DerivationPath.UsageModel? = nil,
                                              includeUnconfirmed: Bool = true) async throws -> OpalBase.Transaction.HistoryModel.ChangeSet {
            try await account.refreshTransactionHistory(using: addressReader,
                                                        usage: usage,
                                                        includeUnconfirmed: includeUnconfirmed,
                                                        transactionReader: transactionReader)
        }
        
        public func refreshTransactionHistory(forAccountAt unhardenedIndex: UInt32,
                                              in wallet: OpalBase.Wallet,
                                              usage: OpalBase.DerivationPath.UsageModel? = nil,
                                              includeUnconfirmed: Bool = true) async throws -> OpalBase.Transaction.HistoryModel.ChangeSet {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await refreshTransactionHistory(for: account,
                                                       usage: usage,
                                                       includeUnconfirmed: includeUnconfirmed)
        }
        
        public func updateTransactionConfirmations(for account: OpalBase.Account,
                                                   transactionHashes: [OpalBase.Transaction.HashModel]) async throws -> OpalBase.Transaction.HistoryModel.ChangeSet {
            try await account.updateTransactionConfirmations(using: transactionHandler,
                                                             for: transactionHashes)
        }
        
        public func updateTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                                   in wallet: OpalBase.Wallet,
                                                   transactionHashes: [OpalBase.Transaction.HashModel]) async throws -> OpalBase.Transaction.HistoryModel.ChangeSet {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await updateTransactionConfirmations(for: account,
                                                            transactionHashes: transactionHashes)
        }
        
        public func refreshTransactionConfirmations(for account: OpalBase.Account) async throws -> OpalBase.Transaction.HistoryModel.ChangeSet {
            try await account.refreshTransactionConfirmations(using: transactionHandler)
        }
        
        public func refreshTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                                    in wallet: OpalBase.Wallet) async throws -> OpalBase.Transaction.HistoryModel.ChangeSet {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await refreshTransactionConfirmations(for: account)
        }
        
        public func makeMonitor(for account: OpalBase.Account,
                                blockHeaderReader: OpalBase.Network.BlockHeaderReadable,
                                includeUnconfirmed: Bool = true,
                                retryDelay: Duration = .seconds(2)) -> Monitor {
            Monitor(account: account,
                    addressReader: addressReader,
                    blockHeaderReader: blockHeaderReader,
                    transactionHandler: transactionHandler,
                    transactionReader: transactionReader,
                    includeUnconfirmed: includeUnconfirmed,
                    retryDelay: retryDelay)
        }
        
        public func makeMonitor(forAccountAt unhardenedIndex: UInt32,
                                in wallet: OpalBase.Wallet,
                                blockHeaderReader: OpalBase.Network.BlockHeaderReadable,
                                includeUnconfirmed: Bool = true,
                                retryDelay: Duration = .seconds(2)) async throws -> Monitor {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return makeMonitor(for: account,
                               blockHeaderReader: blockHeaderReader,
                               includeUnconfirmed: includeUnconfirmed,
                               retryDelay: retryDelay)
        }
        
        public func makeEventStream(for account: OpalBase.Account,
                                    blockHeaderReader: OpalBase.Network.BlockHeaderReadable,
                                    includeUnconfirmed: Bool = true,
                                    retryDelay: Duration = .seconds(2)) async -> AsyncThrowingStream<Monitor.Event, Swift.Error> {
            let monitor = makeMonitor(for: account,
                                      blockHeaderReader: blockHeaderReader,
                                      includeUnconfirmed: includeUnconfirmed,
                                      retryDelay: retryDelay)
            return await monitor.makeEventStream()
        }
        
        public func makeEventStream(forAccountAt unhardenedIndex: UInt32,
                                    in wallet: OpalBase.Wallet,
                                    blockHeaderReader: OpalBase.Network.BlockHeaderReadable,
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

private extension _OpalBase.Wallet.Fulcrum {
    static func makeBalance(from balance: OpalBase.Network.AddressBalance) throws -> OpalBase.Satoshi {
        let positiveUnconfirmed: UInt64
        if balance.unconfirmed > 0 {
            guard let value = UInt64(exactly: balance.unconfirmed) else {
                throw OpalBase.Satoshi.Error.exceedsMaximumAmount
            }
            positiveUnconfirmed = value
        } else {
            positiveUnconfirmed = 0
        }
        
        let confirmed = try OpalBase.Satoshi(balance.confirmed)
        return try confirmed + OpalBase.Satoshi(positiveUnconfirmed)
    }
}
