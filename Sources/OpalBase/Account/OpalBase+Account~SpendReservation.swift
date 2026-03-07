// OpalBase+Account~SpendReservation.swift

import Foundation

extension _OpalBase.Account {
    func reserveSpendAndDeriveKeys(
        utxos: [OpalBase.Transaction.OutputModel.Unspent],
        changeEntry: OpalBase.Address.Book.EntryModel,
        tokenSelectionPolicy: OpalBase.Address.Book.CoinSelectionModel.TokenSelectionPolicy,
        mapReservationError: (Swift.Error) -> OpalBase.Account.Error
    ) async throws -> (
        reservation: OpalBase.Address.Book.SpendReservationModel,
        reservedChangeEntry: OpalBase.Address.Book.EntryModel,
        privateKeys: [OpalBase.Transaction.OutputModel.Unspent: OpalBase.PrivateKey]
    ) {
        let reservation: OpalBase.Address.Book.SpendReservationModel
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

