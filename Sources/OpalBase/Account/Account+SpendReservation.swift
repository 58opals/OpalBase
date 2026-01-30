// Account+SpendReservation.swift

import Foundation

extension Account {
    struct SpendReservation: Sendable {
        let addressBook: Address.Book
        let reservation: Address.Book.SpendReservation
        
        var reservationDate: Date { reservation.reservationDate }
        var changeEntry: Address.Book.Entry { reservation.changeEntry }
        
        func complete() async throws {
            try await addressBook.releaseSpendReservation(reservation, outcome: .completed)
        }
        
        func cancel() async throws {
            try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
        }
    }
}

extension Account.SpendReservation {
    func buildAndBroadcast<Result>(
        build: @Sendable () throws -> Result,
        transaction: @Sendable (Result) -> Transaction,
        via handler: Network.TransactionHandling,
        mapBroadcastError: @Sendable (Swift.Error) -> Account.Error
    ) async throws -> (hash: Transaction.Hash, result: Result) {
        try await Transaction.BroadcastPlanner.buildAndBroadcast(
            build: build,
            transaction: transaction,
            via: handler,
            mapBroadcastError: mapBroadcastError,
            onSuccess: { try await self.complete() }
        )
    }
}
