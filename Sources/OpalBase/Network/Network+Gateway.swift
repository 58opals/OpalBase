// Network+Gateway.swift

import Foundation

extension Network {
    public actor Gateway {
        private let client: Client
        private var mempool: Set<Transaction.Hash> = []
        
        public init(client: Client) {
            self.client = client
        }
        
        public func transaction(for hash: Transaction.Hash) async throws -> Transaction? {
            try await client.fetch(hash)
        }
        
        public func refreshMempool() async throws {
            do {
                mempool = try await client.currentMempool()
            } catch {
                throw Error.mempoolFetchFailed(error)
            }
        }
        
        public func broadcast(_ transaction: Transaction) async throws -> Transaction.Hash {
            let hash = Transaction.Hash(naturalOrder: HASH256.hash(transaction.encode()))
            guard !mempool.contains(hash) else { return hash }
            do {
                try await client.broadcast(transaction)
                mempool.insert(hash)
                return hash
            } catch {
                throw Error.broadcastFailed(error)
            }
        }
        
        public func isInMempool(_ hash: Transaction.Hash) -> Bool {
            mempool.contains(hash)
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
        lhs.localizedDescription == rhs.localizedDescription
    }
}

// MARK: - SwiftFulcrum
import SwiftFulcrum

extension Network.Gateway {
    public struct FulcrumClient: Client {
        private let fulcrum: SwiftFulcrum.Fulcrum
        public init(fulcrum: SwiftFulcrum.Fulcrum) { self.fulcrum = fulcrum }
        public func currentMempool() async throws -> Set<Transaction.Hash> { [] }
        public func broadcast(_ tx: Transaction) async throws {
            _ = try await tx.broadcast(using: fulcrum)
        }
        public func fetch(_ hash: Transaction.Hash) async throws -> Transaction? {
            try? await Transaction.fetchTransaction(for: hash.originalData, using: fulcrum)
        }
    }
}
