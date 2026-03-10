// OpalBase+Account+SpendReservation.swift

import Foundation

extension _OpalBase.Account {
    struct SpendReservation: Sendable {
        let addressBook: OpalBase.Address.Book
        let reservation: OpalBase.Address.Book.SpendReservation
        
        var reservationDate: Date { reservation.reservationDate }
        var changeEntry: OpalBase.Address.Book.Entry { reservation.changeEntry }
        
        func complete() async throws {
            try await addressBook.releaseSpendReservation(reservation, outcome: .completed)
        }
        
        func cancel() async throws {
            try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
        }
    }
}

extension _OpalBase.Account.SpendReservation {
    func buildAndBroadcast<Result>(
        build: @Sendable () throws -> Result,
        transaction: @Sendable (Result) -> OpalBase.Transaction,
        via handler: OpalBase.Network.TransactionClient,
        mapBroadcastError: @Sendable (Swift.Error) -> OpalBase.Account.Error
    ) async throws -> (hash: OpalBase.Transaction.Hash, result: Result) {
        try await OpalBase.Transaction.BroadcastPlanner.buildAndBroadcast(
            build: build,
            transaction: transaction,
            via: handler,
            mapBroadcastError: mapBroadcastError,
            onSuccess: { try await self.complete() }
        )
    }
}
