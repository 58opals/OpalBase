// Network+Gateway.swift

import Foundation

extension Network {
    public actor Gateway {
        private let client: Client
        private var mempool: Set<Transaction.Hash> = []
        private var mempoolLastRefresh: Date = .distantPast
        private let mempoolTTL: TimeInterval
        private let seen: Storage.Repository.TTLCache<Transaction.Hash, Bool>
        
        public init(client: Client, mempoolTTL: TimeInterval = 30, seenTTL: TimeInterval = 600) {
            self.client = client
            self.mempoolTTL = mempoolTTL
            self.seen = .init(defaultTTL: seenTTL)
        }
        
        public func transaction(for hash: Transaction.Hash) async throws -> Transaction? {
            try await client.fetch(hash)
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
            
            do {
                let acknowledged = try await client.broadcast(transaction)
                mempool.insert(acknowledged)
                if acknowledged != expectedHash {
                    mempool.insert(expectedHash)
                }
                await seen.set(expectedHash, true)
                if acknowledged != expectedHash {
                    await seen.set(expectedHash, true)
                }
                return acknowledged
            } catch {
                throw Error.broadcastFailed(error)
            }
        }
        
        public func rawTransaction(for hash: Transaction.Hash) async throws -> Data {
            try await client.getRawTransaction(for: hash)
        }
        
        public func detailedTransaction(for hash: Transaction.Hash) async throws -> Transaction.Detailed {
            try await client.getDetailedTransaction(for: hash)
        }
        
        public func estimateFee(targetBlocks: Int) async throws -> Satoshi {
            try await client.getEstimateFee(targetBlocks: targetBlocks)
        }
        
        public func relayFee() async throws -> Satoshi {
            try await client.getRelayFee()
        }
        
        public func header(height: UInt32) async throws -> HeaderPayload? {
            try await client.getHeader(height: height)
        }
        
        public func pingHeadersTip() async throws {
            try await client.pingHeadersTip()
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
