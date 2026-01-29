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
