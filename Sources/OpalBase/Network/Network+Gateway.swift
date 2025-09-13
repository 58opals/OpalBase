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
                do {
                    mempool = try await client.currentMempool()
                    mempoolLastRefresh = now
                } catch {
                    throw Error.mempoolFetchFailed(error)
                }
            }
            return mempool
        }
        
        public func refreshMempool() async throws {
            _ = try await currentMempool(forceRefresh: true)
        }
        
        public func broadcast(_ transaction: Transaction) async throws -> Transaction.Hash {
            let hash = Transaction.Hash(naturalOrder: HASH256.hash(transaction.encode()))
            
            if await seen.get(hash) != nil { return hash }
            let pool = try await currentMempool()
            guard !pool.contains(hash) else {
                await seen.set(hash, true)
                return hash
            }
            
            do {
                try await client.broadcast(transaction)
                mempool.insert(hash)
                await seen.set(hash, true)
                return hash
            } catch {
                throw Error.broadcastFailed(error)
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

// MARK: - SwiftFulcrum
import SwiftFulcrum

extension Network.Gateway {
    public struct FulcrumClient: Client {
        private let fulcrum: SwiftFulcrum.Fulcrum
        public init(fulcrum: SwiftFulcrum.Fulcrum) { self.fulcrum = fulcrum }
        public func currentMempool() async throws -> Set<Transaction.Hash> { [] }
        public func broadcast(_ transaction: Transaction) async throws {
            _ = try await transaction.broadcast(using: fulcrum)
        }
        public func fetch(_ hash: Transaction.Hash) async throws -> Transaction? {
            try? await Transaction.fetchTransaction(for: hash, using: fulcrum)
        }
    }
}
