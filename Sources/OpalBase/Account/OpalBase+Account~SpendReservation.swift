// OpalBase+Account~SpendReservation.swift

import Foundation

extension _OpalBase.Account {
    func reserveSpendAndDeriveSigningKeys(
        utxos: [OpalBase.Transaction.Output.Unspent],
        changeEntry: OpalBase.Address.Book.Entry,
        tokenSelectionPolicy: OpalBase.Address.Book.CoinSelection.TokenSelectionPolicy,
        mapReservationError: (Swift.Error) -> OpalBase.Account.Error
    ) async throws -> (
        reservation: OpalBase.Address.Book.SpendReservation,
        reservedChangeEntry: OpalBase.Address.Book.Entry,
        signingKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey]
    ) {
        try requirePrivateKeyMaterial()

        let reservation: OpalBase.Address.Book.SpendReservation
        do {
            reservation = try await addressBook.reserveSpend(utxos: utxos,
                                                             changeEntry: changeEntry,
                                                             tokenSelectionPolicy: tokenSelectionPolicy)
        } catch {
            throw mapReservationError(error)
        }
        
        do {
            let keys = try await addressBook.deriveSigningKeys(for: utxos)
            return (reservation, reservation.changeEntry, keys)
        } catch {
            do {
                try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
            } catch let releaseError {
                throw Error.transactionBuildFailed(releaseError)
            }
            if case OpalBase.Address.Book.Error.privateKeyNotFound = error {
                throw Error.privateKeyMaterialUnavailable
            }
            throw Error.transactionBuildFailed(error)
        }
    }

}
