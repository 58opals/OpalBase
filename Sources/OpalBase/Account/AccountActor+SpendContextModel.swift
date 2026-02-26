// AccountActor+SpendContextModel.swift

import Foundation

extension AccountActor {
    struct SpendContextModel {
        let reservationHandle: SpendReservationModel
        let privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel]
        let changeOutput: TransactionModel.OutputModel
        let totalSelectedAmount: SatoshiModel
        let targetAmount: SatoshiModel
    }
    
    func reserveSpendContext(
        inputs: [TransactionModel.OutputModel.UnspentModel],
        outputs: [TransactionModel.OutputModel],
        changeEntry: AddressModel.BookActor.EntryModel,
        tokenSelectionPolicy: AddressModel.BookActor.CoinSelectionModel.TokenSelectionPolicy,
        mapReservationError: @escaping @Sendable (Swift.Error) -> AccountActor.Error,
        mapInsufficientFundsError: @autoclosure () -> AccountActor.Error
    ) async throws -> SpendContextModel {
        let totalSelectedAmount = try inputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try SatoshiModel($0.value)
        }
        let targetAmount = try outputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try SatoshiModel($0.value)
        }
        let changeAmount: SatoshiModel
        do {
            changeAmount = try totalSelectedAmount - targetAmount
        } catch let error as SatoshiModel.Error {
            switch error {
            case .negativeResult:
                throw mapInsufficientFundsError()
            default:
                throw Error.transactionBuildFailed(error)
            }
        } catch {
            throw Error.transactionBuildFailed(error)
        }
        
        let (reservation, reservedChangeEntry, privateKeys) = try await reserveSpendAndDeriveKeys(
            utxos: inputs,
            changeEntry: changeEntry,
            tokenSelectionPolicy: tokenSelectionPolicy,
            mapReservationError: mapReservationError
        )
        let reservationHandle = AccountActor.SpendReservationModel(addressBook: addressBook, reservation: reservation)
        let changeOutput = TransactionModel.OutputModel(value: changeAmount.uint64, address: reservedChangeEntry.address)
        
        return SpendContextModel(reservationHandle: reservationHandle,
                            privateKeys: privateKeys,
                            changeOutput: changeOutput,
                            totalSelectedAmount: totalSelectedAmount,
                            targetAmount: targetAmount)
    }
}
