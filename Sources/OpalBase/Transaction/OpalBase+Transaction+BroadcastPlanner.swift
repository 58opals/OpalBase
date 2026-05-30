// OpalBase+Transaction+BroadcastPlanner.swift

import Foundation

extension _OpalBase.Transaction {
    enum BroadcastPlanner {
        static func buildAndBroadcast<Result, Failure: Swift.Error>(
            build: @Sendable () throws -> Result,
            transaction: @Sendable (Result) -> OpalBase.Transaction,
            via transactionClient: OpalBase.Network.TransactionClient,
            mapBroadcastError: @Sendable (Swift.Error) -> Failure,
            onSuccess: @Sendable () async throws -> Void
        ) async throws -> (hash: OpalBase.Transaction.Hash, result: Result) {
            let result = try build()
            
            let hash: OpalBase.Transaction.Hash
            do {
                hash = try await transactionClient.broadcast(transaction: transaction(result))
            } catch {
                if error.isCancellationError {
                    throw error
                }
                throw mapBroadcastError(error)
            }
            
            try await onSuccess()
            return (hash: hash, result: result)
        }
    }
}
