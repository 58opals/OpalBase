// Transaction+BroadcastPlanner.swift

import Foundation

extension Transaction {
    enum BroadcastPlanner {
        static func buildAndBroadcast<Result>(
            build: () throws -> Result,
            transaction: (Result) -> Transaction,
            via handler: Network.TransactionHandling,
            mapBroadcastError: (Swift.Error) -> Account.Error,
            onSuccess: () async throws -> Void
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
