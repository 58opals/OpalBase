// AccountActor~TokenSpendPlanning.swift

import Foundation

extension AccountActor {
    public func prepareTokenSpend(_ transfer: TokenTransferModel,
                                  feePolicy: WalletActor.FeePolicy = .init()) async throws -> TokenSpendPlanModel {
        guard !transfer.recipients.isEmpty || !transfer.burns.isEmpty else {
            throw Error.tokenTransferHasNoRecipients
        }
        
        let unsafeRecipients = transfer.recipients.filter { !$0.address.isTokenAware }
        if !unsafeRecipients.isEmpty {
            throw Error.tokenSendRequiresTokenAwareAddress(unsafeRecipients.map(\.address))
        }
        
        let requirementsByCategory = try makeTokenRequirementsByCategory(for: transfer)
        let spendableOutputs = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        let tokenChangeAddress = try AddressModel(script: changeEntry.address.lockingScript, format: .tokenAware)
        var spendableTokenByCategory: [CashTokensModel.CategoryIDModel: [TransactionModel.OutputModel.UnspentModel]] = .init()
        for unspentOutput in spendableOutputs {
            guard let category = unspentOutput.tokenData?.category else { continue }
            spendableTokenByCategory[category, default: .init()].append(unspentOutput)
        }
        
        var selectedTokenInputs: [TransactionModel.OutputModel.UnspentModel] = .init()
        selectedTokenInputs.reserveCapacity(spendableOutputs.count)
        var tokenChangeOutputs: [TransactionModel.OutputModel] = .init()
        tokenChangeOutputs.reserveCapacity(requirementsByCategory.count)
        let orderedCategories = requirementsByCategory.keys.sorted { left, right in
            left.transactionOrderData.lexicographicallyPrecedes(right.transactionOrderData)
        }
        for category in orderedCategories {
            guard let requirements = requirementsByCategory[category] else { continue }
            guard let spendableForCategory = spendableTokenByCategory[category],
                  !spendableForCategory.isEmpty else {
                throw Error.tokenTransferInsufficientTokens
            }
            let selected = try selectTokenInputs(from: spendableForCategory, requirements: requirements)
            selectedTokenInputs.append(contentsOf: selected)
            let inventory = try makeTokenInventory(from: selected, category: category)
            let remaining = try subtractTokenInventory(input: inventory, requirements: requirements)
            let hasRemainingFungible = remaining.fungibleAmount > 0
            let hasRemainingNonFungible = remaining.nonFungibleTokens.values.contains { $0 > 0 }
            if hasRemainingFungible || hasRemainingNonFungible {
                tokenChangeOutputs.append(contentsOf: try makeTokenChangeOutputs(from: remaining,
                                                                                 changeAddress: tokenChangeAddress))
            }
        }
        
        let rawRecipientOutputs = transfer.recipients.map { recipient in
            TransactionModel.OutputModel(value: recipient.amount.uint64,
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
        let reservedSpendContext = try await reserveSpendContext(
            inputs: inputs,
            outputs: organizedTokenOutputs,
            changeEntry: changeEntry,
            tokenSelectionPolicy: .allowTokenUTXOs,
            mapReservationError: { Error.tokenSelectionFailed($0) },
            mapInsufficientFundsError: Error.transactionBuildFailed(SatoshiModel.Error.negativeResult)
        )
        
        return TokenSpendPlanModel(transfer: transfer,
                              feeRate: feeRate,
                              tokenInputs: selectedTokenInputs,
                              bitcoinCashInputs: bitcoinCashInputs,
                              tokenRecipientOutputs: rawRecipientOutputs,
                              tokenChangeOutputs: tokenChangeOutputs,
                              bitcoinCashChangeOutput: reservedSpendContext.changeOutput,
                              shouldAllowDustDonation: transfer.shouldAllowDustDonation,
                              reservationHandle: reservedSpendContext.reservationHandle,
                              privateKeys: reservedSpendContext.privateKeys,
                              organizedTokenOutputs: organizedTokenOutputs,
                              shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }
}
