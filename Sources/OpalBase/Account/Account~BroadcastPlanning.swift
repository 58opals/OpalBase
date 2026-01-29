// Account~BroadcastPlanning.swift

import Foundation

extension Account {
    static func planBuildAndBroadcast<Result>(
        build: @Sendable () throws -> Result,
        transaction: @Sendable (Result) -> Transaction,
        via handler: Network.TransactionHandling,
        mapBroadcastError: @Sendable (Swift.Error) -> Account.Error,
        onSuccess: @Sendable () async throws -> Void
    ) async throws -> (hash: Transaction.Hash, result: Result) {
        try await Transaction.BroadcastPlanner.buildAndBroadcast(
            build: build,
            transaction: transaction,
            via: handler,
            mapBroadcastError: mapBroadcastError,
            onSuccess: onSuccess
        )
    }
}
