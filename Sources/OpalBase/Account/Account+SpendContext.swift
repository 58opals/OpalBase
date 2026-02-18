// Account+SpendContext.swift

import Foundation

extension Account {
    struct SpendContext {
        let reservationHandle: SpendReservation
        let privateKeys: [Transaction.Output.Unspent: PrivateKey]
        let changeOutput: Transaction.Output
        let totalSelectedAmount: Satoshi
        let targetAmount: Satoshi
    }
    
    func reserveSpendContext(
        inputs: [Transaction.Output.Unspent],
        outputs: [Transaction.Output],
        changeEntry: Address.Book.Entry,
        tokenSelectionPolicy: Address.Book.CoinSelection.TokenSelectionPolicy,
        mapReservationError: @escaping @Sendable (Swift.Error) -> Account.Error,
        mapInsufficientFundsError: @autoclosure () -> Account.Error
    ) async throws -> SpendContext {
        let totalSelectedAmount = try inputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try Satoshi($0.value)
        }
        let targetAmount = try outputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try Satoshi($0.value)
        }
        let changeAmount: Satoshi
        do {
            changeAmount = try totalSelectedAmount - targetAmount
        } catch let error as Satoshi.Error {
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
        let reservationHandle = Account.SpendReservation(addressBook: addressBook, reservation: reservation)
        let changeOutput = Transaction.Output(value: changeAmount.uint64, address: reservedChangeEntry.address)
        
        return SpendContext(reservationHandle: reservationHandle,
                            privateKeys: privateKeys,
                            changeOutput: changeOutput,
                            totalSelectedAmount: totalSelectedAmount,
                            targetAmount: targetAmount)
    }
}
