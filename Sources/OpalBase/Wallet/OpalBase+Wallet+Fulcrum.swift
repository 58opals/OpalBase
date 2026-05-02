// OpalBase+Wallet+Fulcrum.swift

import Foundation

extension _OpalBase.Wallet {
    /// Fulcrum-backed wallet orchestration for balances, history,
    /// confirmations, and monitoring.
    public actor Fulcrum {
        private let addressReader: OpalBase.Network.AddressReader
        private let blockHeaderReader: OpalBase.Network.BlockHeaderReader
        private let transactionClient: OpalBase.Network.TransactionClient
        private let transactionReader: OpalBase.Network.TransactionReader?

        
        public init(
            client: OpalBase.Network.Fulcrum.Client,
            timeouts: OpalBase.Network.FulcrumRequestTimeout = .init(),
            transactionCache: OpalBase.Transaction.Cache = .init()
        ) {
            self.addressReader = .init(.init(client: client, timeouts: timeouts))
            self.blockHeaderReader = .init(.init(client: client, timeouts: timeouts))
            self.transactionClient = .init(.init(client: client, timeouts: timeouts))
            self.transactionReader = .init(
                .init(client: client, timeouts: timeouts, cache: transactionCache)
            )
        }

        public init(addressReader: OpalBase.Network.AddressReader,
                    blockHeaderReader: OpalBase.Network.BlockHeaderReader,
                    transactionClient: OpalBase.Network.TransactionClient,
                    transactionReader: OpalBase.Network.TransactionReader? = nil) {
            self.addressReader = addressReader
            self.blockHeaderReader = blockHeaderReader
            self.transactionClient = transactionClient
            self.transactionReader = transactionReader
        }

        init(addressReader: any OpalBase.Network.AddressReadable,
             transactionHandler: any OpalBase.Network.TransactionConfirmationClient,
             transactionReader: (any OpalBase.Network.TransactionReadableClient)? = nil) {
            self.addressReader = .init(addressReader)
            self.blockHeaderReader = Self.makePlaceholderBlockHeaderReader()
            self.transactionClient = .init(confirmations: transactionHandler)
            self.transactionReader = transactionReader.map(OpalBase.Network.TransactionReader.init(_:))
        }
        
        public func refreshBalances(for account: OpalBase.Account,
                                    usage: OpalBase.Key.DerivationPath.Usage? = nil,
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
                                    usage: OpalBase.Key.DerivationPath.Usage? = nil,
                                    includeUnconfirmedHistory: Bool = true) async throws -> OpalBase.Account.BalanceRefresh {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await refreshBalances(for: account,
                                             usage: usage,
                                             includeUnconfirmedHistory: includeUnconfirmedHistory)
        }
        
        public func refreshTransactionHistory(for account: OpalBase.Account,
                                              usage: OpalBase.Key.DerivationPath.Usage? = nil,
                                              includeUnconfirmed: Bool = true) async throws -> OpalBase.Transaction.History.ChangeSet {
            try await account.refreshTransactionHistory(using: addressReader,
                                                        usage: usage,
                                                        includeUnconfirmed: includeUnconfirmed,
                                                        transactionReader: transactionReader)
        }
        
        public func refreshTransactionHistory(forAccountAt unhardenedIndex: UInt32,
                                              in wallet: OpalBase.Wallet,
                                              usage: OpalBase.Key.DerivationPath.Usage? = nil,
                                              includeUnconfirmed: Bool = true) async throws -> OpalBase.Transaction.History.ChangeSet {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await refreshTransactionHistory(for: account,
                                                       usage: usage,
                                                       includeUnconfirmed: includeUnconfirmed)
        }
        
        public func updateTransactionConfirmations(for account: OpalBase.Account,
                                                   transactionHashes: [OpalBase.Transaction.Hash]) async throws -> OpalBase.Transaction.History.ChangeSet {
            try await account.updateTransactionConfirmations(using: transactionClient,
                                                             for: transactionHashes)
        }
        
        public func updateTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                                   in wallet: OpalBase.Wallet,
                                                   transactionHashes: [OpalBase.Transaction.Hash]) async throws -> OpalBase.Transaction.History.ChangeSet {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await updateTransactionConfirmations(for: account,
                                                            transactionHashes: transactionHashes)
        }
        
        public func refreshTransactionConfirmations(for account: OpalBase.Account) async throws -> OpalBase.Transaction.History.ChangeSet {
            try await account.refreshTransactionConfirmations(using: transactionClient)
        }
        
        public func refreshTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                                    in wallet: OpalBase.Wallet) async throws -> OpalBase.Transaction.History.ChangeSet {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await refreshTransactionConfirmations(for: account)
        }
        
        public func makeMonitor(for account: OpalBase.Account,
                                includeUnconfirmed: Bool = true,
                                retryDelay: Duration = .seconds(2)) -> Monitor {
            Monitor(account: account,
                    addressReader: addressReader,
                    blockHeaderReader: blockHeaderReader,
                    transactionClient: transactionClient,
                    transactionReader: transactionReader,
                    includeUnconfirmed: includeUnconfirmed,
                    retryDelay: retryDelay)
        }
        
        public func makeMonitor(forAccountAt unhardenedIndex: UInt32,
                                in wallet: OpalBase.Wallet,
                                includeUnconfirmed: Bool = true,
                                retryDelay: Duration = .seconds(2)) async throws -> Monitor {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return makeMonitor(for: account,
                               includeUnconfirmed: includeUnconfirmed,
                               retryDelay: retryDelay)
        }
        
        public func makeEventStream(for account: OpalBase.Account,
                                    includeUnconfirmed: Bool = true,
                                    retryDelay: Duration = .seconds(2)) async -> AsyncThrowingStream<Monitor.Event, Swift.Error> {
            let monitor = makeMonitor(for: account,
                                      includeUnconfirmed: includeUnconfirmed,
                                      retryDelay: retryDelay)
            return await monitor.makeEventStream()
        }
        
        public func makeEventStream(forAccountAt unhardenedIndex: UInt32,
                                    in wallet: OpalBase.Wallet,
                                    includeUnconfirmed: Bool = true,
                                    retryDelay: Duration = .seconds(2)) async throws -> AsyncThrowingStream<Monitor.Event, Swift.Error> {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return await makeEventStream(for: account,
                                         includeUnconfirmed: includeUnconfirmed,
                                         retryDelay: retryDelay)
        }

        func makeMonitor(for account: OpalBase.Account,
                         blockHeaderReader: any OpalBase.Network.BlockHeaderReadable,
                         includeUnconfirmed: Bool = true,
                         retryDelay: Duration = .seconds(2)) -> Monitor {
            Monitor(account: account,
                    addressReader: addressReader,
                    blockHeaderReader: .init(blockHeaderReader),
                    transactionClient: transactionClient,
                    transactionReader: transactionReader,
                    includeUnconfirmed: includeUnconfirmed,
                    retryDelay: retryDelay)
        }

        func makeMonitor(forAccountAt unhardenedIndex: UInt32,
                         in wallet: OpalBase.Wallet,
                         blockHeaderReader: any OpalBase.Network.BlockHeaderReadable,
                         includeUnconfirmed: Bool = true,
                         retryDelay: Duration = .seconds(2)) async throws -> Monitor {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return makeMonitor(for: account,
                               blockHeaderReader: blockHeaderReader,
                               includeUnconfirmed: includeUnconfirmed,
                               retryDelay: retryDelay)
        }

        func makeEventStream(for account: OpalBase.Account,
                             blockHeaderReader: any OpalBase.Network.BlockHeaderReadable,
                             includeUnconfirmed: Bool = true,
                             retryDelay: Duration = .seconds(2)) async -> AsyncThrowingStream<Monitor.Event, Swift.Error> {
            let monitor = makeMonitor(for: account,
                                      blockHeaderReader: blockHeaderReader,
                                      includeUnconfirmed: includeUnconfirmed,
                                      retryDelay: retryDelay)
            return await monitor.makeEventStream()
        }

        func makeEventStream(forAccountAt unhardenedIndex: UInt32,
                             in wallet: OpalBase.Wallet,
                             blockHeaderReader: any OpalBase.Network.BlockHeaderReadable,
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
    static func makePlaceholderBlockHeaderReader() -> OpalBase.Network.BlockHeaderReader {
        OpalBase.Network.BlockHeaderReader(
            fetchTip: { .init(height: 0, headerHexadecimal: "") },
            subscribeToTip: {
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        )
    }

    static func makeBalance(from balance: OpalBase.Network.AddressBalance) throws -> OpalBase.Satoshi {
        guard let confirmed = Int64(exactly: balance.confirmed) else {
            throw OpalBase.Satoshi.Error.exceedsMaximumAmount
        }

        let (total, overflow) = confirmed.addingReportingOverflow(balance.unconfirmed)
        guard !overflow else {
            throw OpalBase.Satoshi.Error.exceedsMaximumAmount
        }
        guard total >= 0 else {
            throw OpalBase.Satoshi.Error.negativeResult
        }

        return try OpalBase.Satoshi(UInt64(total))
    }
}
