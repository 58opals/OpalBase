// OpalBase+Account+SpendReservation.swift

import Foundation

extension _OpalBase.Account {
    struct SpendReservation: Sendable {
        let addressBook: OpalBase.Address.Book
        let reservation: OpalBase.Address.Book.SpendReservation
        
        var reservationDate: Date { reservation.reservationDate }
        var changeEntry: OpalBase.Address.Book.Entry { reservation.changeEntry }

        func requireActive() async throws {
            let activeReservations = await addressBook.readActiveSpendReservations()
            guard activeReservations.contains(where: {
                $0.id == reservation.id && $0.reservationDate == reservation.reservationDate
            }) else {
                throw OpalBase.Account.Error.transactionBuildFailed(
                    OpalBase.Address.Book.Error.spendReservationNotFound
                )
            }
        }
        
        func complete() async throws {
            do {
                try await addressBook.completeSpendReservation(reservation)
            } catch {
                throw OpalBase.Account.Error.transactionBuildFailed(error)
            }
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
