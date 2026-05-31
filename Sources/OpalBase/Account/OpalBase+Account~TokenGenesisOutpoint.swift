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
        
        let genesisOutpointValue: OpalBase.Satoshi
        do {
            genesisOutpointValue = try inputValue - OpalBase.Satoshi(estimatedFeeValue)
        } catch let error as OpalBase.Satoshi.Error {
            switch error {
            case .negativeResult:
                throw Error.tokenGenesisInvalidGenesisInput
            case .exceedsMaximumAmount:
                throw Error.paymentExceedsMaximumAmount
            default:
                throw Error.transactionBuildFailed(error)
            }
        }
        let dustThreshold: UInt64
        do {
            dustThreshold = try outputTemplate.calculateDustThreshold(
                feeRate: OpalBase.Transaction.minimumRelayFeeRate
            )
        } catch {
            throw Error.transactionBuildFailed(error)
        }
        guard genesisOutpointValue.uint64 >= dustThreshold else {
            throw Error.tokenGenesisInvalidGenesisInput
        }
        
        let (reservation, reservedEntry, privateKeys) = try await reserveSpendAndDeriveKeys(
            utxos: [selectedOutput],
            changeEntry: changeEntry,
            tokenSelectionPolicy: .excludeTokenUTXOs,
            mapReservationError: { Error.coinSelectionFailed($0) }
        )
        let reservationHandle = OpalBase.Account.SpendReservation(addressBook: addressBook, reservation: reservation)
        let payment = Payment(recipients: [
            Payment.Recipient(address: reservedEntry.address, amount: genesisOutpointValue)
        ])
        
        let recipientOutput = OpalBase.Transaction.Output(value: genesisOutpointValue.uint64, address: reservedEntry.address)
        let changeOutput = OpalBase.Transaction.Output(value: estimatedFeeValue, address: reservedEntry.address)
        
        return SpendPlan(payment: payment,
                         feeRate: feeRate,
                         inputs: [selectedOutput],
                         totalSelectedAmount: inputValue,
                         targetAmount: genesisOutpointValue,
                         shouldAllowDustDonation: false,
                         reservationHandle: reservationHandle,
                         changeOutput: changeOutput,
                         recipientOutputs: [recipientOutput],
                         privateKeys: privateKeys,
                         shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }
}
