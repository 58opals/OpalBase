//  AccountActor~SpendReservationModel.swift

import Foundation

extension AccountActor {
    func reserveSpendAndDeriveKeys(
        utxos: [TransactionModel.OutputModel.UnspentModel],
        changeEntry: AddressModel.BookActor.EntryModel,
        tokenSelectionPolicy: AddressModel.BookActor.CoinSelectionModel.TokenSelectionPolicy,
        mapReservationError: (Swift.Error) -> AccountActor.Error
    ) async throws -> (
        reservation: AddressModel.BookActor.SpendReservationModel,
        reservedChangeEntry: AddressModel.BookActor.EntryModel,
        privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel]
    ) {
        let reservation: AddressModel.BookActor.SpendReservationModel
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
