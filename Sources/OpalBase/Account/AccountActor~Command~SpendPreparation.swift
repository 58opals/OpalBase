// AccountActor~Command~SpendPreparation.swift

import Foundation

// MARK: - Spend
extension AccountActor {
    public func prepareSpend(_ payment: PaymentModel,
                             feePolicy: WalletActor.FeePolicy = .init()) async throws -> SpendPlanModel {
        guard !payment.recipients.isEmpty else { throw Error.paymentHasNoRecipients }
        
        if payment.recipients.contains(where: { $0.tokenData != nil }) { throw Error.paymentDoesNotSupportTokensUseTokenTransfer }
        if payment.tokenSelectionPolicy == .allowTokenUTXOs { throw Error.paymentCannotSpendTokenUTXOs }
        
        let targetAmount = try payment.recipients.sumSatoshi(or: Error.paymentExceedsMaximumAmount) { recipient in
            recipient.amount
        }
        
        let feeRate = feePolicy.recommendFeeRate(for: payment.feeContext,
                                                 override: payment.feeOverride)
        let rawRecipientOutputs = payment.recipients.map { recipient in
            TransactionModel.OutputModel(value: recipient.amount.uint64,
                               address: recipient.address,
                               tokenData: nil)
        }
        let organizedRecipientOutputs = await privacyShaper.organizeOutputs(rawRecipientOutputs)
        
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        
        let coinSelectionConfiguration = AddressModel.BookActor.CoinSelectionModel.Configuration(recipientOutputs: organizedRecipientOutputs,
                                                                                  changeLockingScript: changeEntry.address.lockingScript.data,
                                                                                  strategy: payment.coinSelection,
                                                                                  shouldAllowDustDonation: payment.shouldAllowDustDonation,
                                                                                  tokenSelectionPolicy: .excludeTokenUTXOs)
        
        let selectedUTXOs: [TransactionModel.OutputModel.UnspentModel]
        do {
            selectedUTXOs = try await addressBook.selectUTXOs(targetAmount: targetAmount,
                                                              feePolicy: feePolicy,
                                                              recommendationContext: payment.feeContext,
                                                              override: payment.feeOverride,
                                                              configuration: coinSelectionConfiguration)
        } catch {
            throw Error.coinSelectionFailed(error)
        }
        
        let heuristicallyOrderedInputs = await privacyShaper.applyCoinSelectionHeuristics(to: selectedUTXOs)
        
        let totalSelectedAmount = try heuristicallyOrderedInputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) { input in
            try SatoshiModel(input.value)
        }
        
        guard totalSelectedAmount >= targetAmount else {
            let requiredAdditionalAmount: UInt64
            do {
                let shortfall = try targetAmount - totalSelectedAmount
                requiredAdditionalAmount = shortfall.uint64
            } catch {
                requiredAdditionalAmount = targetAmount.uint64
            }
            
            throw Error.coinSelectionFailed(TransactionModel.Error.insufficientFunds(required: requiredAdditionalAmount))
        }
        
        let initialChangeAmount: SatoshiModel
        do {
            initialChangeAmount = try totalSelectedAmount - targetAmount
        } catch {
            throw Error.paymentExceedsMaximumAmount
        }
        let initialChangeValue = initialChangeAmount.uint64
        
        let (reservation, reservedChangeEntry, privateKeys) = try await reserveSpendAndDeriveKeys(
            utxos: heuristicallyOrderedInputs,
            changeEntry: changeEntry,
            tokenSelectionPolicy: .excludeTokenUTXOs,
            mapReservationError: { Error.coinSelectionFailed($0) }
        )
        let reservationHandle = AccountActor.SpendReservationModel(addressBook: addressBook, reservation: reservation)
        let changeOutput = TransactionModel.OutputModel(value: initialChangeValue, address: reservedChangeEntry.address)
        
        return SpendPlanModel(payment: payment,
                         feeRate: feeRate,
                         inputs: heuristicallyOrderedInputs,
                         totalSelectedAmount: totalSelectedAmount,
                         targetAmount: targetAmount,
                         shouldAllowDustDonation: payment.shouldAllowDustDonation,
                         reservationHandle: reservationHandle,
                         changeOutput: changeOutput,
                         recipientOutputs: organizedRecipientOutputs,
                         privateKeys: privateKeys,
                         shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }
}
