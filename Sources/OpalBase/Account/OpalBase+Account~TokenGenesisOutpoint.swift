// OpalBase+Account~TokenGenesisOutpoint.swift

import Foundation

extension _OpalBase.Account {
    public func prepareTokenGenesisOutpoint(
        feePolicy: OpalBase.Wallet.FeePolicy = .init(),
        using entryUsage: OpalBase.Key.DerivationPath.Usage = .change
    ) async throws -> SpendPlan {
        let spendableOutputs = await addressBook.listSpendableUTXOs()
        guard let selectedOutput = selectMaximumSpendableOutput(from: spendableOutputs,
                                                                matching: { $0.tokenData == nil }) else {
            throw Error.tokenGenesisNoEligibleGenesisInput
        }
        
        let feeRate = feePolicy.recommendFeeRate()
        let changeEntry = try await addressBook.selectNextEntry(for: entryUsage)
        let outputTemplate = OpalBase.Transaction.Output(value: 0, address: changeEntry.address)
        
        let estimatedFeeValue: UInt64
        do {
            estimatedFeeValue = try OpalBase.Transaction.estimateFee(inputCount: 1,
                                                            outputs: [outputTemplate],
                                                            feePerByte: feeRate)
        } catch {
            throw Error.transactionBuildFailed(error)
        }
        
        let inputValue: OpalBase.Satoshi
        do {
            inputValue = try OpalBase.Satoshi(selectedOutput.value)
        } catch {
            throw Error.paymentExceedsMaximumAmount
        }
        
        let estimatedFee: OpalBase.Satoshi
        do {
            estimatedFee = try OpalBase.Satoshi(estimatedFeeValue)
        } catch let error as OpalBase.Satoshi.Error {
            switch error {
            case .exceedsMaximumAmount:
                throw Error.paymentExceedsMaximumAmount
            default:
                throw Error.transactionBuildFailed(error)
            }
        }
        
        let outputValue: OpalBase.Satoshi
        do {
            outputValue = try inputValue - estimatedFee
        } catch let error as OpalBase.Satoshi.Error {
            switch error {
            case .negativeResult:
                throw Error.tokenGenesisInvalidGenesisInput
            default:
                throw Error.transactionBuildFailed(error)
            }
        }
        
        let (reservation, reservedEntry, privateKeys) = try await reserveSpendAndDeriveKeys(
            utxos: [selectedOutput],
            changeEntry: changeEntry,
            tokenSelectionPolicy: .excludeTokenUTXOs,
            mapReservationError: { Error.coinSelectionFailed($0) }
        )
        let reservationHandle = OpalBase.Account.SpendReservation(addressBook: addressBook, reservation: reservation)
        let payment = Payment(recipients: [
            Payment.Recipient(address: reservedEntry.address, amount: outputValue)
        ])
        
        let recipientOutput = OpalBase.Transaction.Output(value: outputValue.uint64, address: reservedEntry.address)
        let changeOutput = OpalBase.Transaction.Output(value: estimatedFee.uint64, address: reservedEntry.address)
        
        return SpendPlan(payment: payment,
                         feeRate: feeRate,
                         inputs: [selectedOutput],
                         totalSelectedAmount: inputValue,
                         targetAmount: outputValue,
                         shouldAllowDustDonation: false,
                         reservationHandle: reservationHandle,
                         changeOutput: changeOutput,
                         recipientOutputs: [recipientOutput],
                         privateKeys: privateKeys,
                         shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }
}
