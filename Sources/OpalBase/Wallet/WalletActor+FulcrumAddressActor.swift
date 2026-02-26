// WalletActor+FulcrumAddressActor.swift

import Foundation

extension WalletActor {
    public actor FulcrumAddressActor {
        private let addressReader: NetworkModel.AddressReadable
        private let transactionHandler: NetworkModel.TransactionConfirmationClient
        private let transactionReader: NetworkModel.TransactionReadableClient?
        
        public init(addressReader: NetworkModel.AddressReadable,
                    transactionHandler: NetworkModel.TransactionConfirmationClient,
                    transactionReader: NetworkModel.TransactionReadableClient? = nil) {
            self.addressReader = addressReader
            self.transactionHandler = transactionHandler
            self.transactionReader = transactionReader
        }
        
        public func refreshBalances(for account: AccountActor,
                                    usage: DerivationPathModel.UsageModel? = nil,
                                    includeUnconfirmedHistory: Bool = true) async throws -> AccountActor.BalanceRefreshModel {
            _ = try await account.scanForUsedAddresses(using: addressReader,
                                                       usage: usage,
                                                       includeUnconfirmed: includeUnconfirmedHistory)
            return try await account.refreshBalances(for: usage) { address in
                let balance = try await self.addressReader.fetchBalance(for: address.string, tokenFilter: .include)
                return try Self.makeBalance(from: balance)
            }
        }
        
        public func refreshBalances(forAccountAt unhardenedIndex: UInt32,
                                    in wallet: WalletActor,
                                    usage: DerivationPathModel.UsageModel? = nil,
                                    includeUnconfirmedHistory: Bool = true) async throws -> AccountActor.BalanceRefreshModel {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await refreshBalances(for: account,
                                             usage: usage,
                                             includeUnconfirmedHistory: includeUnconfirmedHistory)
        }
        
        public func refreshTransactionHistory(for account: AccountActor,
                                              usage: DerivationPathModel.UsageModel? = nil,
                                              includeUnconfirmed: Bool = true) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
            try await account.refreshTransactionHistory(using: addressReader,
                                                        usage: usage,
                                                        includeUnconfirmed: includeUnconfirmed,
                                                        transactionReader: transactionReader)
        }
        
        public func refreshTransactionHistory(forAccountAt unhardenedIndex: UInt32,
                                              in wallet: WalletActor,
                                              usage: DerivationPathModel.UsageModel? = nil,
                                              includeUnconfirmed: Bool = true) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await refreshTransactionHistory(for: account,
                                                       usage: usage,
                                                       includeUnconfirmed: includeUnconfirmed)
        }
        
        public func updateTransactionConfirmations(for account: AccountActor,
                                                   transactionHashes: [TransactionModel.HashModel]) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
            try await account.updateTransactionConfirmations(using: transactionHandler,
                                                             for: transactionHashes)
        }
        
        public func updateTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                                   in wallet: WalletActor,
                                                   transactionHashes: [TransactionModel.HashModel]) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await updateTransactionConfirmations(for: account,
                                                            transactionHashes: transactionHashes)
        }
        
        public func refreshTransactionConfirmations(for account: AccountActor) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
            try await account.refreshTransactionConfirmations(using: transactionHandler)
        }
        
        public func refreshTransactionConfirmations(forAccountAt unhardenedIndex: UInt32,
                                                    in wallet: WalletActor) async throws -> TransactionModel.HistoryModel.ChangeSetModel {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return try await refreshTransactionConfirmations(for: account)
        }
        
        public func makeMonitor(for account: AccountActor,
                                blockHeaderReader: NetworkModel.BlockHeaderReadable,
                                includeUnconfirmed: Bool = true,
                                retryDelay: Duration = .seconds(2)) -> MonitorActor {
            MonitorActor(account: account,
                    addressReader: addressReader,
                    blockHeaderReader: blockHeaderReader,
                    transactionHandler: transactionHandler,
                    transactionReader: transactionReader,
                    includeUnconfirmed: includeUnconfirmed,
                    retryDelay: retryDelay)
        }
        
        public func makeMonitor(forAccountAt unhardenedIndex: UInt32,
                                in wallet: WalletActor,
                                blockHeaderReader: NetworkModel.BlockHeaderReadable,
                                includeUnconfirmed: Bool = true,
                                retryDelay: Duration = .seconds(2)) async throws -> MonitorActor {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return makeMonitor(for: account,
                               blockHeaderReader: blockHeaderReader,
                               includeUnconfirmed: includeUnconfirmed,
                               retryDelay: retryDelay)
        }
        
        public func makeEventStream(for account: AccountActor,
                                    blockHeaderReader: NetworkModel.BlockHeaderReadable,
                                    includeUnconfirmed: Bool = true,
                                    retryDelay: Duration = .seconds(2)) async -> AsyncThrowingStream<MonitorActor.Event, Swift.Error> {
            let monitor = makeMonitor(for: account,
                                      blockHeaderReader: blockHeaderReader,
                                      includeUnconfirmed: includeUnconfirmed,
                                      retryDelay: retryDelay)
            return await monitor.makeEventStream()
        }
        
        public func makeEventStream(forAccountAt unhardenedIndex: UInt32,
                                    in wallet: WalletActor,
                                    blockHeaderReader: NetworkModel.BlockHeaderReadable,
                                    includeUnconfirmed: Bool = true,
                                    retryDelay: Duration = .seconds(2)) async throws -> AsyncThrowingStream<MonitorActor.Event, Swift.Error> {
            let account = try await wallet.fetchAccount(at: unhardenedIndex)
            return await makeEventStream(for: account,
                                         blockHeaderReader: blockHeaderReader,
                                         includeUnconfirmed: includeUnconfirmed,
                                         retryDelay: retryDelay)
        }
    }
}

private extension WalletActor.FulcrumAddressActor {
    static func makeBalance(from balance: NetworkModel.AddressBalanceModel) throws -> SatoshiModel {
        let positiveUnconfirmed: UInt64
        if balance.unconfirmed > 0 {
            guard let value = UInt64(exactly: balance.unconfirmed) else {
                throw SatoshiModel.Error.exceedsMaximumAmount
            }
            positiveUnconfirmed = value
        } else {
            positiveUnconfirmed = 0
        }
        
        let confirmed = try SatoshiModel(balance.confirmed)
        return try confirmed + SatoshiModel(positiveUnconfirmed)
    }
}
