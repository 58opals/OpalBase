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
                try requirePrivateKeyMaterial()
                let outputPreparation = try await prepareBCHSpendOutputs(
                    for: payment,
                    feePolicy: feePolicy
                )
                let fundingPreparation = try await prepareBCHSpendFunding(
                    for: payment,
                    outputPreparation: outputPreparation,
                    feePolicy: feePolicy
                )

                let (reservation, reservedChangeEntry, signingKeys) = try await reserveSpendAndDeriveSigningKeys(
                    utxos: fundingPreparation.inputs,
                    changeEntry: fundingPreparation.changeEntry,
                    tokenSelectionPolicy: .excludeTokenUTXOs,
                    mapReservationError: { Error.coinSelectionFailed($0) }
                )
                let reservationHandle = OpalBase.Account.SpendReservation(addressBook: addressBook, reservation: reservation)
                let changeOutput = OpalBase.Transaction.Output(value: fundingPreparation.initialChangeValue, address: reservedChangeEntry.address)

                let plan = SpendPlan(payment: payment,
                                     feeRate: outputPreparation.feeRate,
                                     inputs: fundingPreparation.inputs,
                                     totalSelectedAmount: fundingPreparation.totalSelectedAmount,
                                     targetAmount: outputPreparation.targetAmount,
                                     shouldAllowDustDonation: payment.shouldAllowDustDonation,
                                     reservationHandle: reservationHandle,
                                     changeOutput: changeOutput,
                                     recipientOutputs: outputPreparation.recipientOutputs,
                                     signingKeys: signingKeys,
                                     shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.spendPrepareSucceeded,
                    category: OpalDiagnostics.Category.account,
                    fields: fields + [
                        OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.inputCount, fundingPreparation.inputs.count),
                        OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.outputCount, outputPreparation.recipientOutputs.count)
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

    func prepareSpendForExternalReview(
        _ payment: Payment,
        feePolicy: OpalBase.Wallet.FeePolicy = .init(),
        signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
        unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()
    ) async throws -> OpalBase.WalletUnsignedSpendPlan {
        try await OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("spend_prepare_external_review"),
                OpalDiagnostics.Field.module(),
                OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.recipientCount, payment.recipients.count)
            ]
            OpalDiagnostics.record(
                OpalDiagnostics.Event.spendPrepareStarted,
                category: OpalDiagnostics.Category.account,
                fields: fields
            )

            do {
                let outputPreparation = try await prepareBCHSpendOutputs(
                    for: payment,
                    feePolicy: feePolicy
                )

                try OpalBase.Transaction.requireTransactionSigningSupport(
                    signatureFormat: signatureFormat,
                    unlockers: unlockers.values
                )
                let fundingPreparation = try await prepareBCHSpendFunding(
                    for: payment,
                    outputPreparation: outputPreparation,
                    feePolicy: feePolicy
                )

                let reservation: OpalBase.Address.Book.SpendReservation
                do {
                    reservation = try await addressBook.reserveSpend(
                        utxos: fundingPreparation.inputs,
                        changeEntry: fundingPreparation.changeEntry,
                        tokenSelectionPolicy: .excludeTokenUTXOs
                    )
                } catch {
                    throw Error.coinSelectionFailed(error)
                }
                let reservationHandle = OpalBase.Account.SpendReservation(
                    addressBook: addressBook,
                    reservation: reservation
                )
                let changeOutput = OpalBase.Transaction.Output(
                    value: fundingPreparation.initialChangeValue,
                    address: reservation.changeEntry.address
                )
                let outputOrderingStrategy: OpalBase.Transaction.OutputOrderingStrategy = privacyConfiguration.shouldRandomizeRecipientOrdering
                ? .privacyRandomized
                : .canonicalBIP69
                let envelope: OpalBase.WalletUnsignedTransactionEnvelope
                let orderedEnvelopeInputs: [OpalBase.Transaction.Output.Unspent]
                do {
                    envelope = try OpalBase.Transaction.makeUnsignedTransactionEnvelope(
                        unspentOutputs: fundingPreparation.inputs,
                        recipientOutputs: outputPreparation.recipientOutputs,
                        changeOutput: changeOutput,
                        outputOrderingStrategy: outputOrderingStrategy,
                        signatureFormat: signatureFormat,
                        feePerByte: outputPreparation.feeRate,
                        shouldAllowDustDonation: payment.shouldAllowDustDonation,
                        unlockers: unlockers
                    )
                    orderedEnvelopeInputs = try Self.orderUnspentOutputs(
                        fundingPreparation.inputs,
                        toMatch: envelope.unsignedTransaction.inputs
                    )
                } catch {
                    try await reservationHandle.cancel()
                    throw Error.transactionBuildFailed(error)
                }

                OpalDiagnostics.record(
                    OpalDiagnostics.Event.spendPrepareSucceeded,
                    category: OpalDiagnostics.Category.account,
                    fields: fields + [
                        OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.inputCount, fundingPreparation.inputs.count),
                        OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.outputCount, outputPreparation.recipientOutputs.count)
                    ]
                )

                return OpalBase.WalletUnsignedSpendPlan(
                    payment: payment,
                    feeRate: outputPreparation.feeRate,
                    inputs: orderedEnvelopeInputs,
                    totalSelectedAmount: fundingPreparation.totalSelectedAmount,
                    targetAmount: outputPreparation.targetAmount,
                    envelope: envelope,
                    reservationHandle: reservationHandle
                )
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

private extension _OpalBase.Account {
    static func orderUnspentOutputs(
        _ unspentOutputs: [OpalBase.Transaction.Output.Unspent],
        toMatch inputs: [OpalBase.Transaction.Input]
    ) throws -> [OpalBase.Transaction.Output.Unspent] {
        var remainingUnspentOutputs = unspentOutputs

        return try inputs.map { input in
            guard let index = remainingUnspentOutputs.firstIndex(where: { unspentOutput in
                unspentOutput.previousTransactionHash == input.previousTransactionHash
                    && unspentOutput.previousTransactionOutputIndex == input.previousTransactionOutputIndex
            }) else {
                throw OpalBase.Transaction.Error.cannotCreateTransaction
            }

            return remainingUnspentOutputs.remove(at: index)
        }
    }

    struct BCHSpendOutputPreparation {
        let targetAmount: OpalBase.Satoshi
        let feeRate: UInt64
        let recipientOutputs: [OpalBase.Transaction.Output]
    }

    struct BCHSpendFundingPreparation {
        let changeEntry: OpalBase.Address.Book.Entry
        let inputs: [OpalBase.Transaction.Output.Unspent]
        let totalSelectedAmount: OpalBase.Satoshi
        let initialChangeValue: UInt64
    }

    func prepareBCHSpendFunding(
        for payment: Payment,
        outputPreparation: BCHSpendOutputPreparation,
        feePolicy: OpalBase.Wallet.FeePolicy
    ) async throws -> BCHSpendFundingPreparation {
        let targetAmount = outputPreparation.targetAmount
        let feeRate = outputPreparation.feeRate
        let organizedRecipientOutputs = outputPreparation.recipientOutputs
        let changeEntry = try await addressBook.selectNextEntry(for: .change)

        let coinSelectionConfiguration = OpalBase.Address.Book.CoinSelection.Configuration(
            recipientOutputs: organizedRecipientOutputs,
            changeLockingScript: changeEntry.address.lockingScript.data,
            strategy: payment.coinSelection.addressBookStrategy,
            shouldAllowDustDonation: payment.shouldAllowDustDonation,
            tokenSelectionPolicy: .excludeTokenUTXOs
        )

        let selectedUTXOs: [OpalBase.Transaction.Output.Unspent]
        do {
            selectedUTXOs = try await addressBook.selectUTXOs(
                targetAmount: targetAmount,
                feePolicy: feePolicy,
                recommendationContext: payment.feeContext,
                override: payment.feeOverride,
                configuration: coinSelectionConfiguration
            )
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

        return .init(
            changeEntry: changeEntry,
            inputs: heuristicallyOrderedInputs,
            totalSelectedAmount: totalSelectedAmount,
            initialChangeValue: initialChangeAmount.uint64
        )
    }

    func prepareBCHSpendOutputs(
        for payment: Payment,
        feePolicy: OpalBase.Wallet.FeePolicy
    ) async throws -> BCHSpendOutputPreparation {
        guard !payment.recipients.isEmpty else { throw Error.paymentHasNoRecipients }

        if payment.recipients.contains(where: { $0.tokenData != nil }) { throw Error.paymentDoesNotSupportTokensUseTokenTransfer }
        if payment.tokenInputPolicy == .allowTokenUTXOs { throw Error.paymentCannotSpendTokenUTXOs }

        let targetAmount = try payment.recipients.sumSatoshi(or: Error.paymentExceedsMaximumAmount) { recipient in
            recipient.amount
        }

        let feeRate = feePolicy.recommendFeeRate(
            for: payment.feeContext,
            override: payment.feeOverride
        )
        let rawRecipientOutputs = payment.recipients.map { recipient in
            OpalBase.Transaction.Output(
                value: recipient.amount.uint64,
                address: recipient.address,
                tokenData: nil
            )
        }
        for output in rawRecipientOutputs {
            let dustThreshold = try output.calculateDustThreshold(feeRate: OpalBase.Transaction.minimumRelayFeeRate)
            guard output.value >= dustThreshold else {
                throw Error.coinSelectionFailed(OpalBase.Transaction.Error.outputValueIsLessThanTheDustLimit)
            }
        }
        let recipientOutputs = try await privacyShaper.organizeOutputs(rawRecipientOutputs)

        return BCHSpendOutputPreparation(
            targetAmount: targetAmount,
            feeRate: feeRate,
            recipientOutputs: recipientOutputs
        )
    }
}
