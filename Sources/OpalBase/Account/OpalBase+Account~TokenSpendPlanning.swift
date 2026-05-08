// OpalBase+Account~TokenSpendPlanning.swift

import Foundation

extension _OpalBase.Account {
    public func prepareTokenSpend(_ transfer: TokenTransfer,
                                  feePolicy: OpalBase.Wallet.FeePolicy = .init()) async throws -> TokenSpendPlan {
        try await prepareTokenSpend(
            transfer,
            feePolicy: feePolicy,
            beforeReservation: nil
        )
    }

    func prepareTokenSpend(
        _ transfer: TokenTransfer,
        feePolicy: OpalBase.Wallet.FeePolicy = .init(),
        beforeReservation: (@Sendable (OpalBase.Address.Book.Entry) async throws -> Void)?
    ) async throws -> TokenSpendPlan {
        guard !transfer.recipients.isEmpty || !transfer.burns.isEmpty else {
            throw Error.tokenTransferHasNoRecipients
        }
        try validateTokenData(in: transfer)
        
        let unsafeRecipients = transfer.recipients.filter { !$0.address.isTokenAware }
        if !unsafeRecipients.isEmpty {
            throw Error.tokenSendRequiresTokenAwareAddress(unsafeRecipients.map(\.address))
        }
        
        let requirementsByCategory = try makeTokenRequirementsByCategory(for: transfer)
        let spendableOutputs = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        let tokenChangeAddress = try makeTokenAwareAddress(for: changeEntry)
        var spendableTokenByCategory: [OpalBase.CashTokens.CategoryID: [OpalBase.Transaction.Output.Unspent]] = .init()
        for unspentOutput in spendableOutputs {
            guard let category = unspentOutput.tokenData?.category else { continue }
            spendableTokenByCategory[category, default: .init()].append(unspentOutput)
        }
        
        var selectedTokenInputs: [OpalBase.Transaction.Output.Unspent] = .init()
        selectedTokenInputs.reserveCapacity(spendableOutputs.count)
        var tokenChangeOutputs: [OpalBase.Transaction.Output] = .init()
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
            OpalBase.Transaction.Output(value: recipient.amount.uint64,
                               address: recipient.address,
                               tokenData: recipient.tokenData)
        }
        for output in rawRecipientOutputs {
            let dustThreshold = try output.calculateDustThreshold(feeRate: OpalBase.Transaction.minimumRelayFeeRate)
            guard output.value >= dustThreshold else {
                throw Error.tokenSelectionFailed(OpalBase.Transaction.Error.outputValueIsLessThanTheDustLimit)
            }
        }
        let combinedTokenOutputs = rawRecipientOutputs + tokenChangeOutputs
        let organizedTokenOutputs = await privacyShaper.organizeOutputs(combinedTokenOutputs)
        
        let feeRate = feePolicy.recommendFeeRate(for: transfer.feeContext, override: transfer.feeOverride)
        let bchInputs = try selectBCHInputs(from: spendableOutputs,
                                                            existingInputs: selectedTokenInputs,
                                                            outputs: organizedTokenOutputs,
                                                            feeRate: feeRate,
                                                            shouldAllowDustDonation: transfer.shouldAllowDustDonation,
                                                            changeLockingScript: changeEntry.address.lockingScript.data)
        
        let inputs = selectedTokenInputs + bchInputs
        let reservedSpendContext = try await reserveSpendContext(
            inputs: inputs,
            outputs: organizedTokenOutputs,
            changeEntry: changeEntry,
            tokenSelectionPolicy: .allowTokenUTXOs,
            mapReservationError: { Error.tokenSelectionFailed($0) },
            mapInsufficientFundsError: Error.transactionBuildFailed(OpalBase.Satoshi.Error.negativeResult),
            beforeReservation: beforeReservation
        )

        let resolvedTokenChangeOutputs: [OpalBase.Transaction.Output]
        let resolvedOrganizedTokenOutputs: [OpalBase.Transaction.Output]
        let reservedTokenChangeAddress = try makeTokenAwareAddress(for: reservedSpendContext.changeEntry)
        if reservedTokenChangeAddress == tokenChangeAddress {
            resolvedTokenChangeOutputs = tokenChangeOutputs
            resolvedOrganizedTokenOutputs = organizedTokenOutputs
        } else {
            resolvedTokenChangeOutputs = tokenChangeOutputs.map { output in
                makeRetargetedOutput(output, for: reservedTokenChangeAddress)
            }
            resolvedOrganizedTokenOutputs = replacePlannedOutputs(
                in: organizedTokenOutputs,
                originals: tokenChangeOutputs,
                replacements: resolvedTokenChangeOutputs
            )
        }
        
        return TokenSpendPlan(transfer: transfer,
                              feeRate: feeRate,
                              tokenInputs: selectedTokenInputs,
                              bchInputs: bchInputs,
                              tokenRecipientOutputs: rawRecipientOutputs,
                              tokenChangeOutputs: resolvedTokenChangeOutputs,
                              bchChangeOutput: reservedSpendContext.changeOutput,
                              shouldAllowDustDonation: transfer.shouldAllowDustDonation,
                              reservationHandle: reservedSpendContext.reservationHandle,
                              privateKeys: reservedSpendContext.privateKeys,
                              organizedTokenOutputs: resolvedOrganizedTokenOutputs,
                              shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }

    private func validateTokenData(in transfer: TokenTransfer) throws {
        for recipient in transfer.recipients {
            try validateTransferTokenData(recipient.tokenData)
        }
        for burn in transfer.burns {
            try validateTransferTokenData(burn.tokenData)
        }
    }

    private func validateTransferTokenData(_ tokenData: OpalBase.CashTokens.TokenData) throws {
        do {
            _ = try OpalBase.CashTokens.TokenPrefix.encode(tokenData: tokenData)
        } catch {
            throw Error.tokenTransferInvalidTokenData(error)
        }
    }
}
