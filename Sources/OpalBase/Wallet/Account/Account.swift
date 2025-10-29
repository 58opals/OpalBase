// Account.swift

import Foundation

public actor Account: Identifiable {
    private let rootExtendedPrivateKey: PrivateKey.Extended
    
    let purpose: DerivationPath.Purpose
    let coinType: DerivationPath.CoinType
    let account: DerivationPath.Account
    
    public let id: Data
    
    public var addressBook: Address.Book
    let outbox: Outbox
    
    var balanceMonitorConsumerID: UUID?
    var balanceMonitorTasks: [Task<Void, Never>] = .init()
    var balanceMonitorDebounceTask: Task<Void, Never>?
    var balanceMonitorContinuation: AsyncThrowingStream<Satoshi, Swift.Error>.Continuation?
    var isBalanceMonitoringSuspended = false
    let balanceMonitorDebounceInterval: UInt64 = 100_000_000
    
    public let privacyConfiguration: PrivacyShaper.Configuration
    let privacyShaper: PrivacyShaper
    
    private var networkMonitorTask: Task<Void, Never>?
    let requestRouter = RequestRouter<Request>()
    
    init(fulcrumServerURLs: [String] = .init(),
         rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         account: DerivationPath.Account,
         privacyConfiguration: PrivacyShaper.Configuration = .standard,
         outboxPath: URL? = nil) async throws {
        self.rootExtendedPrivateKey = rootExtendedPrivateKey
        self.purpose = purpose
        self.coinType = coinType
        self.account = account
        
        self.id = try [self.rootExtendedPrivateKey.serialize(), self.purpose.hardenedIndex.data, self.coinType.hardenedIndex.data, self.account.deriveHardenedIndex().data].generateID()
        
        self.addressBook = try await Address.Book(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                                  purpose: purpose,
                                                  coinType: coinType,
                                                  account: account)
        
        let folderURL = outboxPath ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("accountOutbox")
        self.outbox = try .init(folderURL: folderURL)
        
        self.privacyConfiguration = privacyConfiguration
        self.privacyShaper = .init(configuration: privacyConfiguration)
    }
    
    init(from snapshot: Account.Snapshot,
         fulcrumServerURLs: [String] = .init(),
         rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         privacyConfiguration: PrivacyShaper.Configuration = .standard,
         outboxPath: URL? = nil) async throws {
        try await self.init(fulcrumServerURLs: fulcrumServerURLs,
                            rootExtendedPrivateKey: rootExtendedPrivateKey,
                            purpose: purpose,
                            coinType: coinType,
                            account: try .init(rawIndexInteger: snapshot.account),
                            privacyConfiguration: privacyConfiguration,
                            outboxPath: outboxPath)
        try await self.addressBook.applySnapshot(snapshot.addressBook)
    }
    
    deinit {
        networkMonitorTask?.cancel()
    }
}

extension Account {
    public enum Error: Swift.Error {
        case balanceFetchTimeout(Address)
    }
}

extension Account: Equatable {
    public static func == (lhs: Account, rhs: Account) -> Bool {
        lhs.id == rhs.id
    }
}

extension Account {
    public var rawIndex: UInt32 {
        account.unhardenedIndex
    }
    
    public var unhardenedIndex: UInt32 {
        account.unhardenedIndex
    }
    
    public func deriveHardenedIndex() throws -> UInt32 {
        try account.deriveHardenedIndex()
    }
}

extension Account {
    public var derivationPath: (purpose: DerivationPath.Purpose,
                                coinType: DerivationPath.CoinType,
                                account: DerivationPath.Account) {
        return (self.purpose, self.coinType, self.account)
    }
}

extension Account {
    public func loadBalanceFromCache() async throws -> Satoshi {
        try await addressBook.calculateCachedTotalBalance()
    }
}

extension Account {
    func enqueueRequest(for key: Request,
                        priority: TaskPriority? = nil,
                        operation: @escaping @Sendable () async throws -> Void) async {
        let handle = await requestRouter.handle(for: key)
        _ = await handle.enqueue(priority: priority, retryPolicy: .retry, operation: operation)
    }
    
    func performRequest<Value: Sendable>(for key: Request,
                                         priority: TaskPriority? = nil,
                                         retryPolicy: RequestRouter<Request>.RetryPolicy = .retry,
                                         operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        let handle = await requestRouter.handle(for: key)
        return try await handle.perform(priority: priority, retryPolicy: retryPolicy, operation: operation)
    }
    
    public func processQueuedRequests() async {
        await requestRouter.resume()
    }
    
    func suspendQueuedRequests() async {
        await requestRouter.suspend()
    }
    
    func resumeQueuedRequests() async {
        await requestRouter.resume()
    }
    
    public func stopNetworkMonitor() {
        networkMonitorTask?.cancel()
        networkMonitorTask = nil
    }
}
