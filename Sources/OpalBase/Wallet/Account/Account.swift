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
    
    let settings: Storage.Settings
    
    var balanceMonitorConsumerID: UUID?
    var balanceMonitorTasks: [Task<Void, Never>] = .init()
    var balanceMonitorDebounceTask: Task<Void, Never>?
    var balanceMonitorContinuation: AsyncThrowingStream<Satoshi, Swift.Error>.Continuation?
    var isBalanceMonitoringSuspended = false
    let balanceMonitorDebounceInterval: UInt64 = 100_000_000
    
    public let privacyConfiguration: PrivacyShaper.Configuration
    let privacyShaper: PrivacyShaper
    
    private var networkMonitorTask: Task<Void, Never>?
    var outboxBroadcastHandler: (@Sendable (String) async throws -> Void)?
    let requestRouter = RequestRouter<Request>()
    private var feeEstimator: Wallet.FeePolicy.FeeEstimator?
    
    init(fulcrumServerURLs: [String] = .init(),
         rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         account: DerivationPath.Account,
         privacyConfiguration: PrivacyShaper.Configuration = .standard,
         outboxPath: URL? = nil,
         settings: Storage.Settings = .init()) async throws {
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
        self.outbox = try await .init(folderURL: folderURL)
        
        self.privacyConfiguration = privacyConfiguration
        self.privacyShaper = .init(configuration: privacyConfiguration)
        self.settings = settings
    }
    
    init(from snapshot: Account.Snapshot,
         fulcrumServerURLs: [String] = .init(),
         rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         privacyConfiguration: PrivacyShaper.Configuration = .standard,
         outboxPath: URL? = nil,
         settings: Storage.Settings = .init()) async throws {
        try await self.init(fulcrumServerURLs: fulcrumServerURLs,
                            rootExtendedPrivateKey: rootExtendedPrivateKey,
                            purpose: purpose,
                            coinType: coinType,
                            account: try .init(rawIndexInteger: snapshot.account),
                            privacyConfiguration: privacyConfiguration,
                            outboxPath: outboxPath,
                            settings: settings)
        try await self.addressBook.applySnapshot(snapshot.addressBook)
    }
    
    deinit {
        networkMonitorTask?.cancel()
    }
}

extension Account {
    public enum Error: Swift.Error, Equatable {
        case balanceFetchTimeout(Address)
        case paymentHasNoRecipients
        case paymentExceedsMaximumAmount
        case coinSelectionFailed(Swift.Error)
        case transactionBuildFailed(Swift.Error)
        case outboxPersistenceFailed(Swift.Error)
        case broadcastFailed(Swift.Error)
        case feePreferenceUnavailable(Swift.Error)
        
        public static func == (lhs: Account.Error, rhs: Account.Error) -> Bool {
            switch (lhs, rhs) {
            case (.paymentHasNoRecipients, .paymentHasNoRecipients),
                (.paymentExceedsMaximumAmount, .paymentExceedsMaximumAmount):
                return true
            case (.balanceFetchTimeout(let leftAddress), .balanceFetchTimeout(let rightAddress)):
                return leftAddress == rightAddress
            case (.coinSelectionFailed(let leftError), .coinSelectionFailed(let rightError)),
                (.transactionBuildFailed(let leftError), .transactionBuildFailed(let rightError)),
                (.outboxPersistenceFailed(let leftError), .outboxPersistenceFailed(let rightError)),
                (.broadcastFailed(let leftError), .broadcastFailed(let rightError)),
                (.feePreferenceUnavailable(let leftError), .feePreferenceUnavailable(let rightError)):
                return leftError.localizedDescription == rightError.localizedDescription
            default:
                return false
            }
        }
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
                        retryPolicy: RequestRouter<Request>.RetryPolicy = .retry,
                        operation: @escaping @Sendable () async throws -> Void) async {
        let handle = await requestRouter.handle(for: key)
        _ = await handle.enqueue(priority: priority, retryPolicy: retryPolicy, operation: operation)
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
    
    func startNetworkMonitor(using session: Network.FulcrumSession) {
        networkMonitorTask?.cancel()
        
        let account = self
        networkMonitorTask = Task { [weak session] in
            guard let session else { return }
            
            var iterator = await session.makeEventStream().makeAsyncIterator()
            while !Task.isCancelled, let event = await iterator.next() {
                switch event {
                case .didReconnect, .didFallback:
                    await account.handleSessionRecovery(using: session)
                case .didStart:
                    await account.handleSessionRecovery(using: session)
                default:
                    continue
                }
            }
        }
    }
    
    public func stopNetworkMonitor() {
        networkMonitorTask?.cancel()
        networkMonitorTask = nil
    }
}

extension Account {
    func handleSessionRecovery(using session: Network.FulcrumSession) async {
        await session.ensureTelemetryInstalled(for: self)
        await session.ensureSynchronization(for: self)
        await resumeQueuedRequests()
        await resubmitPendingTransactions(using: session)
        await processQueuedRequests()
    }
}

extension Account {
    public func makeOutboxStatusStream() async -> AsyncStream<Outbox.StatusUpdate> {
        await outbox.makeStatusStream()
    }
    
    public func loadOutboxStatuses() async -> [Transaction.Hash: Outbox.Status] {
        await outbox.loadStatuses()
    }
}

extension Account {
    func updateOutboxBroadcastHandler(_ handler: (@Sendable (String) async throws -> Void)?) {
        outboxBroadcastHandler = handler
    }
}

extension Account {
    func updateRequestRouterInstrumentation(_ instrumentation: RequestRouter<Request>.Instrumentation) async {
        await requestRouter.updateInstrumentation(instrumentation)
    }
}

extension Account {
    public func loadTransactionHistory() async -> [Address.Book.History.Transaction.Record] {
        await addressBook.listTransactionHistory()
    }
    
    public func loadLedgerEntries(using storage: Storage) async -> [Storage.AccountSnapshot.TransactionLedger.Entry] {
        let accountIndex = account.unhardenedIndex
        guard let snapshot = await storage.loadAccountSnapshot(for: accountIndex) else { return .init() }
        return snapshot.transactionLedger.entries
    }
    
    public func loadTransactionMetadata(for transactionHash: Transaction.Hash,
                                        using storage: Storage) async -> Storage.AccountSnapshot.TransactionLedger.Entry? {
        let accountIndex = account.unhardenedIndex
        return await storage.loadLedgerEntry(for: transactionHash.naturalOrder, accountIndex: accountIndex)
    }
    
    public func updateTransactionLabel(for transactionHash: Transaction.Hash,
                                       to label: String?,
                                       using storage: Storage) async throws -> Bool {
        try await updateLedgerEntry(for: transactionHash, using: storage) { entry in
            entry.label = label
        }
    }
    
    public func updateTransactionMemo(for transactionHash: Transaction.Hash,
                                      to memo: String?,
                                      using storage: Storage) async throws -> Bool {
        try await updateLedgerEntry(for: transactionHash, using: storage) { entry in
            entry.memo = memo
        }
    }
    
    public func updateTransactionMetadata(for transactionHash: Transaction.Hash,
                                          label: String?,
                                          memo: String?,
                                          using storage: Storage) async throws -> Bool {
        try await updateLedgerEntry(for: transactionHash, using: storage) { entry in
            entry.label = label
            entry.memo = memo
        }
    }
    
    public func loadFeePreference() async throws -> Wallet.FeePolicy.Preference {
        do {
            if let storedPreference = try await settings.loadFeePreference(for: account.unhardenedIndex) {
                return storedPreference
            }
            return .standard
        } catch {
            throw Error.feePreferenceUnavailable(error)
        }
    }
    
    public func updateFeePreference(_ preference: Wallet.FeePolicy.Preference) async throws {
        do {
            try await settings.updateFeePreference(preference, for: account.unhardenedIndex)
        } catch {
            throw Error.feePreferenceUnavailable(error)
        }
    }
    
    public func makeFeePolicy() async throws -> Wallet.FeePolicy {
        let preference = try await loadFeePreference()
        return Wallet.FeePolicy(preference: preference, estimator: feeEstimator)
    }
    
    public func updateFeeEstimator(_ estimator: Wallet.FeePolicy.FeeEstimator?) {
        feeEstimator = estimator
    }
}

extension Account {
    func updateLedgerEntry(for transactionHash: Transaction.Hash,
                           using storage: Storage,
                           applying transform: (inout Storage.AccountSnapshot.TransactionLedger.Entry) -> Void) async throws -> Bool {
        let accountIndex = account.unhardenedIndex
        guard var entry = await storage.loadLedgerEntry(for: transactionHash.naturalOrder, accountIndex: accountIndex) else {
            return false
        }
        
        let originalEntry = entry
        transform(&entry)
        guard entry != originalEntry else { return true }
        
        return try await storage.updateLedgerEntry(entry, for: accountIndex)
    }
}
