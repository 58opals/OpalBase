//  Account~SpendReservation.swift

import Foundation

extension Account {
    func reserveSpendAndDeriveKeys(
        utxos: [Transaction.Output.Unspent],
        changeEntry: Address.Book.Entry,
        tokenSelectionPolicy: Address.Book.CoinSelection.TokenSelectionPolicy,
        mapReservationError: (Swift.Error) -> Account.Error
    ) async throws -> (
        reservation: Address.Book.SpendReservation,
        reservedChangeEntry: Address.Book.Entry,
        privateKeys: [Transaction.Output.Unspent: PrivateKey]
    ) {
        let reservation: Address.Book.SpendReservation
        do {
            reservation = try await addressBook.reserveSpend(utxos: utxos,
                                                             changeEntry: changeEntry,
                                                             tokenSelectionPolicy: tokenSelectionPolicy)
        } catch {
            throw mapReservationError(error)
        }
        
        do {
            let keys = try await addressBook.derivePrivateKeys(for: utxos)
            return (reservation, reservation.changeEntry, keys)
        } catch {
            do {
                try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
            } catch let releaseError {
                throw Error.transactionBuildFailed(releaseError)
            }
            throw Error.transactionBuildFailed(error)
        }
    }
}
