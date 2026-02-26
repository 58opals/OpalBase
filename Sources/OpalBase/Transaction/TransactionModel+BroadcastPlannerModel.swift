// TransactionModel+BroadcastPlannerModel.swift

import Foundation

extension TransactionModel {
    enum BroadcastPlannerModel {
        static func buildAndBroadcast<Result, Failure: Swift.Error>(
            build: @Sendable () throws -> Result,
            transaction: @Sendable (Result) -> TransactionModel,
            via handler: NetworkModel.TransactionHandling,
            mapBroadcastError: @Sendable (Swift.Error) -> Failure,
            onSuccess: @Sendable () async throws -> Void
        ) async throws -> (hash: TransactionModel.HashModel, result: Result) {
            let result = try build()
            
            let hash: TransactionModel.HashModel
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
