// Network+Gateway.swift

import Foundation

extension Network {
    public actor Gateway {
        private let api: API
        private var mempool: Set<Transaction.Hash> = []
        private var mempoolLastRefresh: Date = .distantPast
        private let mempoolTTL: TimeInterval
        private let seen: Storage.Repository.TTLCache<Transaction.Hash, Bool>
        private let requestRouter: RequestRouter<Request>
        
        private var health: HealthSnapshot
        private let headerFreshnessInterval: TimeInterval
        private let healthRetryDelay: TimeInterval
        
        public init(api: API, configuration: Configuration = .init()) {
            self.api = api
            self.mempoolTTL = configuration.mempoolTTL
            self.seen = .init(defaultTTL: configuration.seenTTL)
            self.requestRouter = .init(configuration: configuration.router,
                                       instrumentation: configuration.instrumentation)
            self.health = .init(status: configuration.initialStatus,
                                lastHeaderUpdate: configuration.initialHeaderUpdate)
            self.headerFreshnessInterval = max(0, configuration.headerFreshness)
            self.healthRetryDelay = max(0, configuration.healthRetryDelay)
        }
        
        private func perform<Value: Sendable>(
            _ request: Request,
            priority: TaskPriority? = nil,
            retryPolicy: RequestRouter<Request>.RetryPolicy = .retry,
            operation: @escaping @Sendable () async throws -> Value
        ) async throws -> Value {
            let handle = await requestRouter.handle(for: request)
            do {
                return try await handle.perform(priority: priority,
                                                retryPolicy: retryPolicy,
                                                operation: operation)
            } catch {
                throw try mapToGatewayError(error, for: request)
            }
        }
        
        private func ensureBroadcastEligibility(now: Date = .init()) throws {
            guard health.status == .online else {
                throw Error(reason: .poolUnhealthy(health.status),
                            retry: .after(healthRetryDelay))
            }
            
            guard headerFreshnessInterval > 0 else { return }
            guard let lastHeader = health.lastHeaderUpdate else {
                throw Error(reason: .headersStale(since: nil),
                            retry: .after(healthRetryDelay))
            }
            
            let staleness = now.timeIntervalSince(lastHeader)
            guard staleness <= headerFreshnessInterval else {
                throw Error(reason: .headersStale(since: lastHeader),
                            retry: .after(healthRetryDelay))
            }
        }
        
        private func cacheBroadcast(expected: Transaction.Hash,
                                    acknowledged: Transaction.Hash) async
        {
            await markKnown(hash: acknowledged)
            await markKnown(hash: expected)
        }
        
        private func markKnown(hash: Transaction.Hash) async {
            mempool.insert(hash)
            await seen.set(hash, true)
        }
        
        private func refreshSeenIfPresent(_ hash: Transaction.Hash) async -> Bool {
            guard await seen.get(hash) != nil else { return false }
            await seen.set(hash, true)
            return true
        }
        
        private func cachedMempoolContains(_ hash: Transaction.Hash,
                                           now: Date = .init()) async -> Bool
        {
            if now.timeIntervalSince(mempoolLastRefresh) > mempoolTTL {
                _ = try? await getCurrentMempool(forceRefresh: true)
            }
            
            guard mempool.contains(hash) else { return false }
            await markKnown(hash: hash)
            return true
        }
        
        private func remoteAcknowledges(_ hash: Transaction.Hash) async throws -> Bool {
            do {
                if try await getTransaction(for: hash) != nil {
                    await markKnown(hash: hash)
                    return true
                }
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                return false
            }
            
            return false
        }
        
        private func mapToGatewayError(_ error: Swift.Error, for request: Request) throws -> Error {
            if let cancellation = error as? CancellationError { throw cancellation }
            if let domain = error as? Error { return domain }
            if let normalized = api.normalize(error, during: request) { return normalized }
            let description = String(describing: error)
            return Error(reason: .transport(description: description),
                         retry: .after(healthRetryDelay))
        }
        
        public func getTransaction(for hash: Transaction.Hash) async throws -> Transaction? {
            try await perform(.transaction(hash)) { try await self.api.fetch(hash) }
        }
        
        public func getCurrentMempool(forceRefresh: Bool = false) async throws -> Set<Transaction.Hash> {
            let now = Date()
            if forceRefresh || now.timeIntervalSince(mempoolLastRefresh) > mempoolTTL {
                mempool = api.currentMempool()
                mempoolLastRefresh = now
            }
            return mempool
        }
        
        public func refreshMempool() async throws {
            _ = try await getCurrentMempool(forceRefresh: true)
        }
        
        public func submit(_ rawTransaction: Data) async throws -> Transaction.Hash {
            let (transaction, _) = try Transaction.decode(from: rawTransaction)
            let expectedHash = Transaction.Hash(naturalOrder: HASH256.hash(rawTransaction))
            return try await submit(transaction: transaction,
                                    expectedHash: expectedHash)
        }
        
        public func broadcast(_ transaction: Transaction) async throws -> Transaction.Hash {
            let payload = transaction.encode()
            let expectedHash = Transaction.Hash(naturalOrder: HASH256.hash(payload))
            return try await submit(transaction: transaction,
                                    expectedHash: expectedHash)
        }
        
        private func submit(transaction: Transaction,
                            expectedHash: Transaction.Hash) async throws -> Transaction.Hash {
            let now = Date()
            
            if await refreshSeenIfPresent(expectedHash) { return expectedHash }
            if await cachedMempoolContains(expectedHash, now: now) { return expectedHash }
            if try await remoteAcknowledges(expectedHash) { return expectedHash }
            
            try ensureBroadcastEligibility(now: now)
            
            let request = Network.Gateway.Request.broadcast(expectedHash)
            let handle = await requestRouter.handle(for: request)
            do {
                let acknowledged = try await handle.perform(priority: .high, retryPolicy: .retry) {
                    try await self.api.broadcast(transaction)
                }
                await cacheBroadcast(expected: expectedHash, acknowledged: acknowledged)
                return acknowledged
            } catch {
                if let resolution = api.interpretBroadcastError(error, expectedHash: expectedHash) {
                    switch resolution {
                    case .alreadyKnown(let hash):
                        await cacheBroadcast(expected: expectedHash, acknowledged: hash)
                        return hash
                    case .retry(let normalized):
                        throw normalized
                    }
                }
                throw try mapToGatewayError(error, for: request)
            }
        }
        
        public func getRawTransaction(for hash: Transaction.Hash) async throws -> Data {
            try await perform(.rawTransaction(hash)) {
                try await self.api.getRawTransaction(hash)
            }
        }
        
        public func getDetailedTransaction(for hash: Transaction.Hash) async throws -> Transaction.Detailed {
            try await perform(.detailedTransaction(hash)) {
                try await self.api.getDetailedTransaction(hash)
            }
        }
        
        public func getEstimateFee(targetBlocks: Int) async throws -> Satoshi {
            try await perform(.estimateFee(targetBlocks)) {
                try await self.api.getEstimateFee(targetBlocks)
            }
        }
        
        public func getRelayFee() async throws -> Satoshi {
            try await perform(.relayFee) {
                try await self.api.getRelayFee()
            }
        }
        
        public func getHeader(height: UInt32) async throws -> HeaderPayload? {
            try await perform(.header(height)) {
                try await self.api.getHeader(height)
            }
        }
        
        public func pingHeadersTip() async throws {
            try await perform(.pingHeadersTip) {
                try await self.api.pingHeadersTip()
            }
        }
        
        public func isInMempool(_ hash: Transaction.Hash) -> Bool {
            mempool.contains(hash)
        }
        
        public func markSeen(_ hash: Transaction.Hash) async {
            await seen.set(hash, true)
        }
        
        public func updateHealth(status: Network.Wallet.Status, lastHeaderAt: Date? = nil) {
            health.status = status
            if let lastHeaderAt { health.lastHeaderUpdate = lastHeaderAt }
        }
        
        public func resetHeaderFreshness() {
            health.lastHeaderUpdate = nil
        }
        
        public func currentHealth() -> HealthSnapshot { health }
    }
}

extension Network.Gateway {
    public struct Error: Swift.Error, Sendable, Equatable {
        public enum Reason: Sendable, Equatable {
            case poolUnhealthy(Network.Wallet.Status)
            case headersStale(since: Date?)
            case rejected(code: Int?, message: String)
            case transport(description: String)
        }
        
        public enum RetryHint: Sendable, Equatable {
            case immediately
            case after(TimeInterval)
            case never
        }
        
        public let reason: Reason
        public let retry: RetryHint
        
        public init(reason: Reason, retry: RetryHint) {
            self.reason = reason
            self.retry = retry
        }
    }
}

extension Network.Gateway {
    public enum BroadcastResolution: Sendable, Equatable {
        case retry(Error)
        case alreadyKnown(Transaction.Hash)
    }
}

extension Network.Gateway {
    public struct HealthSnapshot: Sendable, Equatable {
        public var status: Network.Wallet.Status
        public var lastHeaderUpdate: Date?
        
        public init(status: Network.Wallet.Status, lastHeaderUpdate: Date?) {
            self.status = status
            self.lastHeaderUpdate = lastHeaderUpdate
        }
    }
}

extension Network.Gateway {
    public enum Request: Hashable, Sendable {
        case transaction(Transaction.Hash)
        case broadcast(Transaction.Hash)
        case rawTransaction(Transaction.Hash)
        case detailedTransaction(Transaction.Hash)
        case estimateFee(Int)
        case relayFee
        case header(UInt32)
        case pingHeadersTip
    }
}

extension Network.Gateway {
    public struct Configuration: Sendable {
        public var mempoolTTL: TimeInterval
        public var seenTTL: TimeInterval
        public var headerFreshness: TimeInterval
        public var healthRetryDelay: TimeInterval
        public var initialStatus: Network.Wallet.Status
        public var initialHeaderUpdate: Date?
        public var router: RequestRouter<Request>.Configuration
        public var instrumentation: RequestRouter<Request>.Instrumentation
        
        public init(mempoolTTL: TimeInterval = 30,
                    seenTTL: TimeInterval = 600,
                    headerFreshness: TimeInterval = 30,
                    healthRetryDelay: TimeInterval = 5,
                    initialStatus: Network.Wallet.Status = .online,
                    initialHeaderUpdate: Date? = Date(),
                    router: RequestRouter<Request>.Configuration = .init(),
                    instrumentation: RequestRouter<Request>.Instrumentation = .init())
        {
            precondition(mempoolTTL >= 0, "mempoolTTL must be non-negative")
            precondition(seenTTL >= 0, "seenTTL must be non-negative")
            precondition(headerFreshness >= 0, "headerFreshness must be non-negative")
            precondition(healthRetryDelay >= 0, "healthRetryDelay must be non-negative")
            
            self.mempoolTTL = mempoolTTL
            self.seenTTL = seenTTL
            self.headerFreshness = headerFreshness
            self.healthRetryDelay = healthRetryDelay
            self.initialStatus = initialStatus
            self.initialHeaderUpdate = initialHeaderUpdate
            self.router = router
            self.instrumentation = instrumentation
        }
    }
}
