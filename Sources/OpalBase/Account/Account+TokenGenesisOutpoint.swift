// Account+TokenGenesisOutpoint.swift

import Foundation

extension Account {
    public func prepareTokenGenesisOutpoint(
        feePolicy: Wallet.FeePolicy = .init(),
        using entryUsage: DerivationPath.Usage = .change
    ) async throws -> SpendPlan {
        let spendableOutputs = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        guard let selectedOutput = spendableOutputs.first(where: { $0.tokenData == nil }) else {
            throw Error.tokenGenesisNoEligibleGenesisInput
        }
        
        let feeRate = feePolicy.recommendFeeRate()
        let changeEntry = try await addressBook.selectNextEntry(for: entryUsage)
        let outputTemplate = Transaction.Output(value: 0, address: changeEntry.address)
        
        let estimatedFeeValue: UInt64
        do {
            estimatedFeeValue = try Transaction.estimateFee(inputCount: 1,
                                                            outputs: [outputTemplate],
                                                            feePerByte: feeRate)
        } catch {
            throw Error.transactionBuildFailed(error)
        }
        
        let inputValue: Satoshi
        do {
            inputValue = try Satoshi(selectedOutput.value)
        } catch {
            throw Error.paymentExceedsMaximumAmount
        }
        
        let estimatedFee: Satoshi
        do {
            estimatedFee = try Satoshi(estimatedFeeValue)
        } catch let error as Satoshi.Error {
            switch error {
            case .exceedsMaximumAmount:
                throw Error.paymentExceedsMaximumAmount
            default:
                throw Error.transactionBuildFailed(error)
            }
        }
        
        let outputValue: Satoshi
        do {
            outputValue = try inputValue - estimatedFee
        } catch let error as Satoshi.Error {
            switch error {
            case .negativeResult:
                throw Error.tokenGenesisInvalidGenesisInput
            default:
                throw Error.transactionBuildFailed(error)
            }
        }
        
        let reservation: Address.Book.SpendReservation
        do {
            reservation = try await addressBook.reserveSpend(utxos: [selectedOutput],
                                                             changeEntry: changeEntry,
                                                             tokenSelectionPolicy: .excludeTokenUTXOs)
        } catch {
            throw Error.coinSelectionFailed(error)
        }
        
        let reservedEntry = reservation.changeEntry
        let payment = Payment(recipients: [
            Payment.Recipient(address: reservedEntry.address, amount: outputValue)
        ])
        
        let recipientOutput = Transaction.Output(value: outputValue.uint64, address: reservedEntry.address)
        let changeOutput = Transaction.Output(value: estimatedFee.uint64, address: reservedEntry.address)
        
        let privateKeys: [Transaction.Output.Unspent: PrivateKey]
        do {
            privateKeys = try await addressBook.derivePrivateKeys(for: [selectedOutput])
        } catch {
            do {
                try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
            } catch let releaseError {
                throw Error.transactionBuildFailed(releaseError)
            }
            throw Error.transactionBuildFailed(error)
        }
        
        return SpendPlan(payment: payment,
                         feeRate: feeRate,
                         inputs: [selectedOutput],
                         totalSelectedAmount: inputValue,
                         targetAmount: outputValue,
                         shouldAllowDustDonation: false,
                         addressBook: addressBook,
                         changeEntry: reservedEntry,
                         reservation: reservation,
                         changeOutput: changeOutput,
                         recipientOutputs: [recipientOutput],
                         privateKeys: privateKeys,
                         shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }
}
