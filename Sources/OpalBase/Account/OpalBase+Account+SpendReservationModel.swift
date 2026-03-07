// OpalBase+Account+SpendReservationModel.swift

import Foundation

extension _OpalBase.Account {
    struct SpendReservationModel: Sendable {
        let addressBook: OpalBase.Address.Book
        let reservation: OpalBase.Address.Book.SpendReservationModel
        
        var reservationDate: Date { reservation.reservationDate }
        var changeEntry: OpalBase.Address.Book.EntryModel { reservation.changeEntry }
        
        func complete() async throws {
            try await addressBook.releaseSpendReservation(reservation, outcome: .completed)
        }
        
        func cancel() async throws {
            try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
        }
    }
}

extension _OpalBase.Account.SpendReservationModel {
    func buildAndBroadcast<Result>(
        build: @Sendable () throws -> Result,
        transaction: @Sendable (Result) -> OpalBase.Transaction,
        via handler: OpalBase.Network.TransactionHandling,
        mapBroadcastError: @Sendable (Swift.Error) -> OpalBase.Account.Error
    ) async throws -> (hash: OpalBase.Transaction.HashModel, result: Result) {
        try await OpalBase.Transaction.BroadcastPlannerModel.buildAndBroadcast(
            build: build,
            transaction: transaction,
            via: handler,
            mapBroadcastError: mapBroadcastError,
            onSuccess: { try await self.complete() }
        )
    }
}
