// Network+Gateway.swift

import Foundation

extension Network {
    public actor Gateway {
        private let client: Client
        private var mempool: Set<Transaction.Hash> = []
        private var mempoolLastRefresh: Date = .distantPast
        private let mempoolTTL: TimeInterval
        private let seen: Storage.Repository.TTLCache<Transaction.Hash, Bool>
        private let requestRouter: RequestRouter<Request>
        
        public init(client: Client, configuration: Configuration = .init()) {
            self.client = client
            self.mempoolTTL = configuration.mempoolTTL
            self.seen = .init(defaultTTL: configuration.seenTTL)
            self.requestRouter = .init(configuration: configuration.router,
                                       instrumentation: configuration.instrumentation)
        }
        
        public func transaction(for hash: Transaction.Hash) async throws -> Transaction? {
            let handle = await requestRouter.handle(for: .transaction(hash))
            return try await handle.perform(retryPolicy: .retry) {
                try await self.client.fetch(hash)
            }
        }
        
        public func currentMempool(forceRefresh: Bool = false) async throws -> Set<Transaction.Hash> {
            let now = Date()
            if forceRefresh || now.timeIntervalSince(mempoolLastRefresh) > mempoolTTL {
                mempool = client.currentMempool
                mempoolLastRefresh = now
            }
            return mempool
        }
        
        public func refreshMempool() async throws {
            _ = try await currentMempool(forceRefresh: true)
        }
        
        public func broadcast(_ transaction: Transaction) async throws -> Transaction.Hash {
            let expectedHash = Transaction.Hash(naturalOrder: HASH256.hash(transaction.encode()))
            if await seen.get(expectedHash) != nil { return expectedHash }
            let pool = try await currentMempool()
            guard !pool.contains(expectedHash) else {
                await seen.set(expectedHash, true)
                return expectedHash
            }
            
            let handle = await requestRouter.handle(for: .broadcast(expectedHash))
            do {
                let acknowledged = try await handle.perform(priority: .high, retryPolicy: .retry) {
                    try await self.client.broadcast(transaction)
                }
                mempool.insert(acknowledged)
                if acknowledged != expectedHash {
                    mempool.insert(expectedHash)
                }
                await seen.set(expectedHash, true)
                if acknowledged != expectedHash {
                    await seen.set(acknowledged, true)
                }
                return acknowledged
            } catch {
                throw Error.broadcastFailed(error)
            }
        }
        
        public func getRawTransaction(for hash: Transaction.Hash) async throws -> Data {
            let handle = await requestRouter.handle(for: .rawTransaction(hash))
            return try await handle.perform(retryPolicy: .retry) {
                try await self.client.getRawTransaction(for: hash)
            }
        }
        
        public func getDetailedTransaction(for hash: Transaction.Hash) async throws -> Transaction.Detailed {
            let handle = await requestRouter.handle(for: .detailedTransaction(hash))
                        return try await handle.perform(retryPolicy: .retry) {
                            try await self.client.getDetailedTransaction(for: hash)
                        }
        }
        
        public func getEstimateFee(targetBlocks: Int) async throws -> Satoshi {
            let handle = await requestRouter.handle(for: .estimateFee(targetBlocks))
                        return try await handle.perform(retryPolicy: .retry) {
                            try await self.client.getEstimateFee(targetBlocks: targetBlocks)
                        }
        }
        
        public func getRelayFee() async throws -> Satoshi {
            let handle = await requestRouter.handle(for: .relayFee)
                        return try await handle.perform(retryPolicy: .retry) {
                            try await self.client.getRelayFee()
                        }
        }
        
        public func getHeader(height: UInt32) async throws -> HeaderPayload? {
            let handle = await requestRouter.handle(for: .header(height))
                        return try await handle.perform(retryPolicy: .retry) {
                            try await self.client.getHeader(height: height)
                        }
        }
        
        public func pingHeadersTip() async throws {
            let handle = await requestRouter.handle(for: .pingHeadersTip)
                        _ = try await handle.perform(retryPolicy: .retry) {
                            try await self.client.pingHeadersTip()
                        }
        }
        
        public func isInMempool(_ hash: Transaction.Hash) -> Bool {
            mempool.contains(hash)
        }
        
        public func markSeen(_ hash: Transaction.Hash) async {
            await seen.set(hash, true)
        }
    }
}

extension Network.Gateway {
    public enum Error: Swift.Error, Sendable {
        case broadcastFailed(Swift.Error)
        case mempoolFetchFailed(Swift.Error)
    }
}

extension Network.Gateway.Error: Equatable {
    public static func == (lhs: Network.Gateway.Error, rhs: Network.Gateway.Error) -> Bool {
        switch (lhs, rhs) {
        case (.broadcastFailed, .broadcastFailed),
            (.mempoolFetchFailed, .mempoolFetchFailed):
            return true
        default:
            return false
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
        public var router: RequestRouter<Request>.Configuration
        public var instrumentation: RequestRouter<Request>.Instrumentation

        public init(mempoolTTL: TimeInterval = 30,
                    seenTTL: TimeInterval = 600,
                    router: RequestRouter<Request>.Configuration = .init(),
                    instrumentation: RequestRouter<Request>.Instrumentation = .init())
        {
            self.mempoolTTL = mempoolTTL
            self.seenTTL = seenTTL
            self.router = router
            self.instrumentation = instrumentation
        }
    }
}
