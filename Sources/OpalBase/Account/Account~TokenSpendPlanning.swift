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
        
        let requirementsByCategory = try makeTokenRequirementsByCategory(for: transfer)
        let spendableOutputs = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        let spendableTokenByCategory = Dictionary(grouping: spendableOutputs.compactMap {
            unspentOutput -> (CashTokens.CategoryID, Transaction.Output.Unspent)? in
            guard let category = unspentOutput.tokenData?.category else { return nil }
            return (category, unspentOutput)
        }, by: { $0.0 }).mapValues { $0.map(\.1) }
        
        var selectedTokenInputs: [Transaction.Output.Unspent] = .init()
        var remainingInventories: [TokenInventory] = .init()
        for (category, requirements) in requirementsByCategory {
            let spendableForCategory = spendableTokenByCategory[category] ?? .init()
            let selected = try selectTokenInputs(from: spendableForCategory, requirements: requirements)
            selectedTokenInputs += selected
            let inventory = try makeTokenInventory(from: selected, category: category)
            let remaining = try subtractTokenInventory(input: inventory, requirements: requirements)
            remainingInventories.append(remaining)
        }
        
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        let tokenChangeAddress = try Address(script: changeEntry.address.lockingScript, format: .tokenAware)
        var tokenChangeOutputs: [Transaction.Output] = .init()
        for remaining in remainingInventories {
            tokenChangeOutputs += try makeTokenChangeOutputs(from: remaining,
                                                             changeAddress: tokenChangeAddress)
        }
        
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
