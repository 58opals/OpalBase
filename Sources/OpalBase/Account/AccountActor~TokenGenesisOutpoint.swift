// AccountActor~TokenGenesisOutpoint.swift

import Foundation

extension AccountActor {
    public func prepareTokenGenesisOutpoint(
        feePolicy: WalletActor.FeePolicy = .init(),
        using entryUsage: DerivationPathModel.UsageModel = .change
    ) async throws -> SpendPlanModel {
        let spendableOutputs = await addressBook.listSpendableUTXOs()
        guard let selectedOutput = selectMaximumSpendableOutput(from: spendableOutputs,
                                                                matching: { $0.tokenData == nil }) else {
            throw Error.tokenGenesisNoEligibleGenesisInput
        }
        
        let feeRate = feePolicy.recommendFeeRate()
        let changeEntry = try await addressBook.selectNextEntry(for: entryUsage)
        let outputTemplate = TransactionModel.OutputModel(value: 0, address: changeEntry.address)
        
        let estimatedFeeValue: UInt64
        do {
            estimatedFeeValue = try TransactionModel.estimateFee(inputCount: 1,
                                                            outputs: [outputTemplate],
                                                            feePerByte: feeRate)
        } catch {
            throw Error.transactionBuildFailed(error)
        }
        
        let inputValue: SatoshiModel
        do {
            inputValue = try SatoshiModel(selectedOutput.value)
        } catch {
            throw Error.paymentExceedsMaximumAmount
        }
        
        let estimatedFee: SatoshiModel
        do {
            estimatedFee = try SatoshiModel(estimatedFeeValue)
        } catch let error as SatoshiModel.Error {
            switch error {
            case .exceedsMaximumAmount:
                throw Error.paymentExceedsMaximumAmount
            default:
                throw Error.transactionBuildFailed(error)
            }
        }
        
        let outputValue: SatoshiModel
        do {
            outputValue = try inputValue - estimatedFee
        } catch let error as SatoshiModel.Error {
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
        let reservationHandle = AccountActor.SpendReservationModel(addressBook: addressBook, reservation: reservation)
        let payment = PaymentModel(recipients: [
            PaymentModel.Recipient(address: reservedEntry.address, amount: outputValue)
        ])
        
        let recipientOutput = TransactionModel.OutputModel(value: outputValue.uint64, address: reservedEntry.address)
        let changeOutput = TransactionModel.OutputModel(value: estimatedFee.uint64, address: reservedEntry.address)
        
        return SpendPlanModel(payment: payment,
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
