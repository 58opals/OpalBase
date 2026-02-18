// Transaction+BroadcastPlanner.swift

import Foundation

extension Transaction {
    enum BroadcastPlanner {
        static func buildAndBroadcast<Result, Failure: Swift.Error>(
            build: @Sendable () throws -> Result,
            transaction: @Sendable (Result) -> Transaction,
            via handler: Network.TransactionHandling,
            mapBroadcastError: @Sendable (Swift.Error) -> Failure,
            onSuccess: @Sendable () async throws -> Void
        ) async throws -> (hash: Transaction.Hash, result: Result) {
            let result = try build()
            
            let hash: Transaction.Hash
            do {
                hash = try await handler.broadcast(transaction: transaction(result))
            } catch {
                throw mapBroadcastError(error)
            }
            
            try await onSuccess()
            return (hash: hash, result: result)
        }
    }
}
