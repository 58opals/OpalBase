// OpalBase+Account+SpendContextModel.swift

import Foundation

extension _OpalBase.Account {
    struct SpendContextModel {
        let reservationHandle: SpendReservationModel
        let privateKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.PrivateKey]
        let changeOutput: OpalBase.Transaction.Output
        let totalSelectedAmount: OpalBase.Satoshi
        let targetAmount: OpalBase.Satoshi
    }
    
    func reserveSpendContext(
        inputs: [OpalBase.Transaction.Output.Unspent],
        outputs: [OpalBase.Transaction.Output],
        changeEntry: OpalBase.Address.Book.Entry,
        tokenSelectionPolicy: OpalBase.Address.Book.CoinSelection.TokenSelectionPolicy,
        mapReservationError: @escaping @Sendable (Swift.Error) -> OpalBase.Account.Error,
        mapInsufficientFundsError: @autoclosure () -> OpalBase.Account.Error
    ) async throws -> SpendContextModel {
        let totalSelectedAmount = try inputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try OpalBase.Satoshi($0.value)
        }
        let targetAmount = try outputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try OpalBase.Satoshi($0.value)
        }
        let changeAmount: OpalBase.Satoshi
        do {
            changeAmount = try totalSelectedAmount - targetAmount
        } catch let error as OpalBase.Satoshi.Error {
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
        let reservationHandle = OpalBase.Account.SpendReservationModel(addressBook: addressBook, reservation: reservation)
        let changeOutput = OpalBase.Transaction.Output(value: changeAmount.uint64, address: reservedChangeEntry.address)
        
        return SpendContextModel(reservationHandle: reservationHandle,
                            privateKeys: privateKeys,
                            changeOutput: changeOutput,
                            totalSelectedAmount: totalSelectedAmount,
                            targetAmount: targetAmount)
    }
}
