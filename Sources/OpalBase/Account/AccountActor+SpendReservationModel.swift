// AccountActor+SpendReservationModel.swift

import Foundation

extension AccountActor {
    struct SpendReservationModel: Sendable {
        let addressBook: AddressModel.BookActor
        let reservation: AddressModel.BookActor.SpendReservationModel
        
        var reservationDate: Date { reservation.reservationDate }
        var changeEntry: AddressModel.BookActor.EntryModel { reservation.changeEntry }
        
        func complete() async throws {
            try await addressBook.releaseSpendReservation(reservation, outcome: .completed)
        }
        
        func cancel() async throws {
            try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
        }
    }
}

extension AccountActor.SpendReservationModel {
    func buildAndBroadcast<Result>(
        build: @Sendable () throws -> Result,
        transaction: @Sendable (Result) -> TransactionModel,
        via handler: NetworkModel.TransactionHandling,
        mapBroadcastError: @Sendable (Swift.Error) -> AccountActor.Error
    ) async throws -> (hash: TransactionModel.HashModel, result: Result) {
        try await TransactionModel.BroadcastPlannerModel.buildAndBroadcast(
            build: build,
            transaction: transaction,
            via: handler,
            mapBroadcastError: mapBroadcastError,
            onSuccess: { try await self.complete() }
        )
    }
}
