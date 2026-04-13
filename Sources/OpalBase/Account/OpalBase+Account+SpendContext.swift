// OpalBase+Account+SpendContext.swift

import Foundation

extension _OpalBase.Account {
    struct SpendContext {
        let reservationHandle: SpendReservation
        let changeEntry: OpalBase.Address.Book.Entry
        let privateKeys: [OpalBase.Transaction.Output.Unspent: Data]
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
        mapInsufficientFundsError: @autoclosure () -> OpalBase.Account.Error,
        beforeReservation: (@Sendable (OpalBase.Address.Book.Entry) async throws -> Void)? = nil
    ) async throws -> SpendContext {
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

        if let beforeReservation {
            try await beforeReservation(changeEntry)
        }
        
        let (reservation, reservedChangeEntry, privateKeys) = try await reserveSpendAndDeriveKeys(
            utxos: inputs,
            changeEntry: changeEntry,
            tokenSelectionPolicy: tokenSelectionPolicy,
            mapReservationError: mapReservationError
        )
        let reservationHandle = OpalBase.Account.SpendReservation(addressBook: addressBook, reservation: reservation)
        let changeOutput = OpalBase.Transaction.Output(value: changeAmount.uint64, address: reservedChangeEntry.address)
        
        return SpendContext(reservationHandle: reservationHandle,
                            changeEntry: reservedChangeEntry,
                            privateKeys: privateKeys,
                            changeOutput: changeOutput,
                            totalSelectedAmount: totalSelectedAmount,
                            targetAmount: targetAmount)
    }

    func makeTokenAwareAddress(for changeEntry: OpalBase.Address.Book.Entry) throws -> OpalBase.Address {
        try OpalBase.Address(script: changeEntry.address.lockingScript, format: .tokenAware)
    }

    func makeRetargetedOutput(_ output: OpalBase.Transaction.Output,
                              for address: OpalBase.Address) -> OpalBase.Transaction.Output {
        OpalBase.Transaction.Output(value: output.value, address: address, tokenData: output.tokenData)
    }

    func replacePlannedOutputs(
        in outputs: [OpalBase.Transaction.Output],
        originals: [OpalBase.Transaction.Output],
        replacements: [OpalBase.Transaction.Output]
    ) -> [OpalBase.Transaction.Output] {
        assert(originals.count == replacements.count)
        guard originals.count == replacements.count, !originals.isEmpty else {
            return outputs
        }

        var remainingReplacements = Array(zip(originals, replacements))
        return outputs.map { output in
            guard let index = remainingReplacements.firstIndex(where: { source, _ in
                source == output
            }) else {
                return output
            }

            let replacement = remainingReplacements.remove(at: index).1
            return replacement
        }
    }
}
