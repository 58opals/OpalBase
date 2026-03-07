// OpalBase.Transaction+BroadcastPlannerModel.swift

import Foundation

extension _OpalBase.Transaction {
    enum BroadcastPlannerModel {
        static func buildAndBroadcast<Result, Failure: Swift.Error>(
            build: @Sendable () throws -> Result,
            transaction: @Sendable (Result) -> OpalBase.Transaction,
            via handler: OpalBase.Network.TransactionHandling,
            mapBroadcastError: @Sendable (Swift.Error) -> Failure,
            onSuccess: @Sendable () async throws -> Void
        ) async throws -> (hash: OpalBase.Transaction.HashModel, result: Result) {
            let result = try build()
            
            let hash: OpalBase.Transaction.HashModel
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
