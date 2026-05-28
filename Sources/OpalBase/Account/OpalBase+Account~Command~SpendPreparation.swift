// OpalBase+Account~Command~SpendPreparation.swift

import Foundation
import OpalDiagnostics

// MARK: - Spend
extension _OpalBase.Account {
    public func prepareSpend(_ payment: Payment,
                             feePolicy: OpalBase.Wallet.FeePolicy = .init()) async throws -> SpendPlan {
        try await OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("spend_prepare"),
                OpalDiagnostics.Field.module(),
                OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.recipientCount, payment.recipients.count)
            ]
            OpalDiagnostics.record(
                OpalDiagnostics.Event.spendPrepareStarted,
                category: OpalDiagnostics.Category.account,
                fields: fields
            )

            do {
                guard !payment.recipients.isEmpty else { throw Error.paymentHasNoRecipients }

                if payment.recipients.contains(where: { $0.tokenData != nil }) { throw Error.paymentDoesNotSupportTokensUseTokenTransfer }
                if payment.tokenInputPolicy == .allowTokenUTXOs { throw Error.paymentCannotSpendTokenUTXOs }

                let targetAmount = try payment.recipients.sumSatoshi(or: Error.paymentExceedsMaximumAmount) { recipient in
                    recipient.amount
                }

                let feeRate = feePolicy.recommendFeeRate(for: payment.feeContext,
                                                         override: payment.feeOverride)
                let rawRecipientOutputs = payment.recipients.map { recipient in
                    OpalBase.Transaction.Output(value: recipient.amount.uint64,
                                       address: recipient.address,
                                       tokenData: nil)
                }
                for output in rawRecipientOutputs {
                    let dustThreshold = try output.calculateDustThreshold(feeRate: OpalBase.Transaction.minimumRelayFeeRate)
                    guard output.value >= dustThreshold else {
                        throw Error.coinSelectionFailed(OpalBase.Transaction.Error.outputValueIsLessThanTheDustLimit)
                    }
                }
                let organizedRecipientOutputs = try await privacyShaper.organizeOutputs(rawRecipientOutputs)

                let changeEntry = try await addressBook.selectNextEntry(for: .change)

                let coinSelectionConfiguration = OpalBase.Address.Book.CoinSelection.Configuration(recipientOutputs: organizedRecipientOutputs,
                                                                                          changeLockingScript: changeEntry.address.lockingScript.data,
                                                                                          strategy: payment.coinSelection.addressBookStrategy,
                                                                                          shouldAllowDustDonation: payment.shouldAllowDustDonation,
                                                                                          tokenSelectionPolicy: .excludeTokenUTXOs)

                let selectedUTXOs: [OpalBase.Transaction.Output.Unspent]
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
                    try OpalBase.Satoshi(input.value)
                }

                guard totalSelectedAmount >= targetAmount else {
                    let requiredAdditionalAmount: UInt64
                    do {
                        let shortfall = try targetAmount - totalSelectedAmount
                        requiredAdditionalAmount = shortfall.uint64
                    } catch {
                        requiredAdditionalAmount = targetAmount.uint64
                    }

                    throw Error.coinSelectionFailed(OpalBase.Transaction.Error.insufficientFunds(required: requiredAdditionalAmount))
                }

                do {
                    let evaluation = try OpalBase.Address.Book.CoinSelection.evaluate(
                        configuration: coinSelectionConfiguration,
                        total: totalSelectedAmount.uint64,
                        inputCount: heuristicallyOrderedInputs.count,
                        targetAmount: targetAmount.uint64,
                        minimumRelayFeeRate: OpalBase.Transaction.minimumRelayFeeRate,
                        feePerByte: feeRate
                    )
                    if evaluation == nil {
                        let feeWithoutChange = try OpalBase.Transaction.estimateFee(
                            inputCount: heuristicallyOrderedInputs.count,
                            outputs: organizedRecipientOutputs,
                            feePerByte: feeRate
                        )
                        let requiredAmount = try targetAmount.uint64.addOrThrow(
                            feeWithoutChange,
                            overflowError: Error.paymentExceedsMaximumAmount
                        )
                        let requiredAdditionalAmount = requiredAmount > totalSelectedAmount.uint64
                        ? requiredAmount - totalSelectedAmount.uint64
                        : 0
                        throw Error.coinSelectionFailed(OpalBase.Transaction.Error.insufficientFunds(required: requiredAdditionalAmount))
                    }
                } catch let error as Error {
                    throw error
                } catch {
                    throw Error.coinSelectionFailed(error)
                }

                let initialChangeAmount: OpalBase.Satoshi
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
                let reservationHandle = OpalBase.Account.SpendReservation(addressBook: addressBook, reservation: reservation)
                let changeOutput = OpalBase.Transaction.Output(value: initialChangeValue, address: reservedChangeEntry.address)

                let plan = SpendPlan(payment: payment,
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
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.spendPrepareSucceeded,
                    category: OpalDiagnostics.Category.account,
                    fields: fields + [
                        OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.inputCount, heuristicallyOrderedInputs.count),
                        OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.outputCount, organizedRecipientOutputs.count)
                    ]
                )
                return plan
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.spendPrepareFailed,
                    category: OpalDiagnostics.Category.account,
                    fields: fields + OpalDiagnostics.Field.errorFields(for: error)
                )
                throw error
            }
        }
    }
}
