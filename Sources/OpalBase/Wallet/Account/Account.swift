// Account.swift

import Foundation

public actor Account: Identifiable {
    public let fulcrumPool: Network.Wallet.FulcrumPool
    public let feeRate: Network.Wallet.FeeRate
    
    private let rootExtendedPrivateKey: PrivateKey.Extended
    
    let purpose: DerivationPath.Purpose
    let coinType: DerivationPath.CoinType
    let account: DerivationPath.Account
    
    public let id: Data
    
    public var addressBook: Address.Book
    let outbox: Outbox
    
    let addressMonitor: Monitor
    
    private var networkMonitorTask: Task<Void, Never>?
    private var requestQueue: [@Sendable () async throws -> Void] = .init()
    
    init(fulcrumServerURLs: [String] = [],
         rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         account: DerivationPath.Account,
         outboxPath: URL? = nil) async throws {
        self.fulcrumPool = try await .init(urls: fulcrumServerURLs)
        self.feeRate = .init(fulcrumPool: self.fulcrumPool)
        
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
        
        self.addressMonitor = .init()
        self.networkMonitorTask = Task { [weak self] in
            guard let self else { return }
            await self.monitorNetworkStatus()
        }
    }
    
    init(from snapshot: Account.Snapshot,
         fulcrumServerURLs: [String] = [],
         rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         outboxPath: URL? = nil) async throws {
        let account = try await Self.init(fulcrumServerURLs: fulcrumServerURLs,
                                          rootExtendedPrivateKey: rootExtendedPrivateKey,
                                          purpose: purpose,
                                          coinType: coinType,
                                          account: try .init(rawIndexInteger: snapshot.account),
                                          outboxPath: outboxPath)
        self.fulcrumPool = account.fulcrumPool
        self.feeRate = account.feeRate
        self.rootExtendedPrivateKey = account.rootExtendedPrivateKey
        self.purpose = account.purpose
        self.coinType = account.coinType
        self.account = account.account
        self.id = account.id
        self.addressBook = await account.addressBook
        self.outbox = account.outbox
        self.addressMonitor = .init()
        
        try await self.addressBook.applySnapshot(snapshot.addressBook)
        
        self.networkMonitorTask = Task { [weak self] in
            guard let self else { return }
            await self.monitorNetworkStatus()
        }
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
    public func getRawIndex() -> UInt32 {
        return self.account.unhardenedIndex
    }
    
    public func getUnhardenedIndex() -> UInt32 {
        return self.account.getUnhardenedIndex()
    }
    
    public func getHardenedIndex() throws -> UInt32 {
        return try self.account.deriveHardenedIndex()
    }
}

extension Account {
    public func getDerivationPath() -> (purpose: DerivationPath.Purpose,
                                        coinType: DerivationPath.CoinType,
                                        account: DerivationPath.Account) {
        return (self.purpose, self.coinType, self.account)
    }
}

extension Account {
    public func getBalanceFromCache() async throws -> Satoshi {
        return try await addressBook.calculateCachedTotalBalance()
    }
}

extension Account {
    func enqueueRequest(_ request: @escaping @Sendable () async throws -> Void) {
        requestQueue.append(request)
    }
    
    public func processQueuedRequests() async {
        guard !requestQueue.isEmpty else { return }
        
        let currentRequests = requestQueue
        requestQueue.removeAll()
        for request in currentRequests {
            do { try await request() }
            catch { requestQueue.append(request) }
        }
    }
    
    public func stopNetworkMonitor() {
        networkMonitorTask?.cancel()
        networkMonitorTask = nil
    }
}
