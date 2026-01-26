// Account~TokenSpendPlanning.swift

import Foundation

extension Account {
    public func prepareTokenSpend(_ transfer: TokenTransfer,
                                  feePolicy: Wallet.FeePolicy = .init()) async throws -> TokenSpendPlan {
        guard !transfer.recipients.isEmpty || !transfer.burns.isEmpty else {
            throw Error.tokenTransferHasNoRecipients
        }
        
        let unsafeRecipients = transfer.recipients.filter { !$0.address.supportsTokens }
        if !unsafeRecipients.isEmpty {
            throw Error.tokenSendRequiresTokenAwareAddress(unsafeRecipients.map(\.address))
        }
        
        let tokenCategory = try resolveTokenCategory(from: transfer)
        let requirements = try makeTokenRequirements(for: transfer, category: tokenCategory)
        let spendableOutputs = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        let spendableTokenOutputs = spendableOutputs.filter { $0.tokenData?.category == tokenCategory }
        let selectedTokenInputs = try selectTokenInputs(from: spendableTokenOutputs, requirements: requirements)
        let tokenInputInventory = try makeTokenInventory(from: selectedTokenInputs, category: tokenCategory)
        let remainingInventory = try subtractTokenInventory(input: tokenInputInventory, requirements: requirements)
        
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        let tokenChangeAddress = try Address(script: changeEntry.address.lockingScript, format: .tokenAware)
        let tokenChangeOutputs = try makeTokenChangeOutputs(from: remainingInventory,
                                                            changeAddress: tokenChangeAddress)
        
        let rawRecipientOutputs = transfer.recipients.map { recipient in
            Transaction.Output(value: recipient.amount.uint64,
                               address: recipient.address,
                               tokenData: recipient.tokenData)
        }
        let combinedTokenOutputs = rawRecipientOutputs + tokenChangeOutputs
        let organizedTokenOutputs = await privacyShaper.organizeOutputs(combinedTokenOutputs)
        
        let feeRate = feePolicy.recommendFeeRate(for: transfer.feeContext, override: transfer.feeOverride)
        let bitcoinCashInputs = try selectBitcoinCashInputs(from: spendableOutputs,
                                                            existingInputs: selectedTokenInputs,
                                                            outputs: organizedTokenOutputs,
                                                            feeRate: feeRate,
                                                            shouldAllowDustDonation: transfer.shouldAllowDustDonation,
                                                            changeLockingScript: changeEntry.address.lockingScript.data)
        
        let inputs = selectedTokenInputs + bitcoinCashInputs
        let totalSelectedAmount = try inputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try Satoshi($0.value)
        }
        let targetAmount = try organizedTokenOutputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try Satoshi($0.value)
        }
        let initialChangeAmount = try totalSelectedAmount - targetAmount
        let changeOutput = Transaction.Output(value: initialChangeAmount.uint64, address: changeEntry.address)
        
        let reservation: Address.Book.SpendReservation
        do {
            reservation = try await addressBook.reserveSpend(utxos: inputs,
                                                             changeEntry: changeEntry,
                                                             tokenSelectionPolicy: .allowTokenUTXOs)
        } catch {
            throw Error.tokenSelectionFailed(error)
        }
        
        let privateKeys: [Transaction.Output.Unspent: PrivateKey]
        do {
            privateKeys = try await addressBook.derivePrivateKeys(for: inputs)
        } catch {
            do {
                try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
            } catch let releaseError {
                throw Error.transactionBuildFailed(releaseError)
            }
            throw Error.transactionBuildFailed(error)
        }
        
        return TokenSpendPlan(transfer: transfer,
                              feeRate: feeRate,
                              tokenInputs: selectedTokenInputs,
                              bitcoinCashInputs: bitcoinCashInputs,
                              tokenRecipientOutputs: rawRecipientOutputs,
                              tokenChangeOutputs: tokenChangeOutputs,
                              bitcoinCashChangeOutput: changeOutput,
                              shouldAllowDustDonation: transfer.shouldAllowDustDonation,
                              addressBook: addressBook,
                              changeEntry: reservation.changeEntry,
                              reservation: reservation,
                              privateKeys: privateKeys,
                              organizedTokenOutputs: organizedTokenOutputs,
                              shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }
}
