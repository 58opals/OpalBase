// Network+TransactionGateway.swift

import Foundation

extension Network {
    public actor TransactionGateway {
        public protocol Client: Sendable {
            func currentMempool() async throws -> Set<Transaction.Hash>
            func broadcast(_ transaction: Transaction) async throws
            func fetch(_ hash: Transaction.Hash) async throws -> Transaction?
        }
        
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

extension Network.TransactionGateway {
    public enum Error: Swift.Error, Sendable {
        case broadcastFailed(Swift.Error)
        case mempoolFetchFailed(Swift.Error)
    }
}

extension Network.TransactionGateway.Error: Equatable {
    public static func == (lhs: Network.TransactionGateway.Error, rhs: Network.TransactionGateway.Error) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
