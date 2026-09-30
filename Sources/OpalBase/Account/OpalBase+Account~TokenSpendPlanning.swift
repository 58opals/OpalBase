// OpalBase+Account~TokenSpendPlanning.swift

import Foundation

extension _OpalBase.Account {
    public func prepareTokenSpend(_ transfer: TokenTransfer,
                                  feePolicy: OpalBase.Wallet.FeePolicy = .init()) async throws -> TokenSpendPlan {
        try await prepareTokenSpend(
            transfer,
            feePolicy: feePolicy,
            payingFeesFrom: nil,
            beforeReservation: nil
        )
    }

    func prepareTokenSpend(
        _ transfer: TokenTransfer,
        feePolicy: OpalBase.Wallet.FeePolicy = .init(),
        payingFeesFrom feePayer: OpalBase.Account? = nil,
        beforeReservation: (@Sendable (OpalBase.Address.Book.Entry) async throws -> Void)?
    ) async throws -> TokenSpendPlan {
        try requirePrivateKeyMaterial()
        let fundingAccount = feePayer ?? self
        let usesSeparatePayer = fundingAccount !== self
        if usesSeparatePayer {
            try await fundingAccount.requirePrivateKeyMaterial()
        }

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
        let tokenChangeEntry = try await addressBook.selectNextEntry(for: .change)
        let fundingBook = fundingAccount.addressBook
        let bchChangeEntry = usesSeparatePayer
            ? try await fundingBook.selectNextEntry(for: .change)
            : tokenChangeEntry
        let tokenChangeAddress = try makeTokenAwareAddress(for: tokenChangeEntry)
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

        // BCH carried by token inputs remains with their account. The separate payer
        // covers recipient BCH and network fees; it does not receive token-input residue.
        var tokenOwnerBCHChangeOutput: OpalBase.Transaction.Output?
        if usesSeparatePayer {
            let tokenInputValue = try selectedTokenInputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
                try OpalBase.Satoshi($0.value)
            }.uint64
            let tokenChangeValue = try tokenChangeOutputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
                try OpalBase.Satoshi($0.value)
            }.uint64
            if tokenInputValue > tokenChangeValue {
                let residue = tokenInputValue - tokenChangeValue
                let candidate = OpalBase.Transaction.Output(value: residue, address: tokenChangeEntry.address)
                let dustThreshold = try candidate.calculateDustThreshold(
                    feeRate: OpalBase.Transaction.minimumRelayFeeRate
                )
                if residue >= dustThreshold {
                    tokenOwnerBCHChangeOutput = candidate
                } else if !tokenChangeOutputs.isEmpty {
                    let original = tokenChangeOutputs[0]
                    let retainedValue = try original.value.addOrThrow(
                        residue,
                        overflowError: Error.paymentExceedsMaximumAmount
                    )
                    tokenChangeOutputs[0] = OpalBase.Transaction.Output(
                        value: retainedValue,
                        address: tokenChangeAddress,
                        tokenData: original.tokenData
                    )
                } else {
                    tokenOwnerBCHChangeOutput = OpalBase.Transaction.Output(
                        value: dustThreshold,
                        address: tokenChangeEntry.address
                    )
                }
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
        let combinedTokenOutputs = rawRecipientOutputs + tokenChangeOutputs + [tokenOwnerBCHChangeOutput].compactMap { $0 }
        let organizedTokenOutputs = try await privacyShaper.organizeOutputs(combinedTokenOutputs)
        
        let feeRate = feePolicy.recommendFeeRate(for: transfer.feeContext, override: transfer.feeOverride)
        let fundingOutputs = usesSeparatePayer
            ? await fundingBook.sortSpendableUTXOs(by: { $0.value > $1.value })
            : spendableOutputs
        let bchInputs = try selectBCHInputs(from: fundingOutputs,
                                                            existingInputs: selectedTokenInputs,
                                                            outputs: organizedTokenOutputs,
                                                            feeRate: feeRate,
                                                            shouldAllowDustDonation: transfer.shouldAllowDustDonation,
                                                            changeLockingScript: bchChangeEntry.address.lockingScript.data,
                                                            minimumBCHInputCount: usesSeparatePayer ? 1 : 0)
        if let duplicatedInput = bchInputs.first(where: { fundingInput in
            selectedTokenInputs.contains { tokenInput in
                tokenInput.previousTransactionHash == fundingInput.previousTransactionHash
                    && tokenInput.previousTransactionOutputIndex == fundingInput.previousTransactionOutputIndex
            }
        }) {
            throw Error.tokenSelectionFailed(OpalBase.Address.Book.Error.utxoDuplicated(duplicatedInput))
        }
        
        let inputs = selectedTokenInputs + bchInputs
        let reservationHandles: [SpendReservation]
        let signingKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey]
        let reservedTokenChangeEntry: OpalBase.Address.Book.Entry
        let reservedBCHChangeEntry: OpalBase.Address.Book.Entry
        let bchChangeOutput: OpalBase.Transaction.Output
        if usesSeparatePayer {
            let selectedAmount = try inputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
                try OpalBase.Satoshi($0.value)
            }
            let outputAmount = try organizedTokenOutputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
                try OpalBase.Satoshi($0.value)
            }
            let changeAmount = try selectedAmount - outputAmount
            let tokenReservation = try await reserveSpendAndDeriveSigningKeys(
                utxos: selectedTokenInputs,
                changeEntry: tokenChangeEntry,
                tokenSelectionPolicy: .allowTokenUTXOs,
                reuseMatchingReservation: false,
                mapReservationError: { Error.tokenSelectionFailed($0) }
            )
            let tokenHandle = SpendReservation(addressBook: addressBook, reservation: tokenReservation.reservation)
            var payerHandle: SpendReservation?
            do {
                try Task.checkCancellation()
                if let beforeReservation {
                    try await beforeReservation(bchChangeEntry)
                }
                let payerReservation = try await fundingAccount.reserveSpendAndDeriveSigningKeys(
                    utxos: bchInputs,
                    changeEntry: bchChangeEntry,
                    tokenSelectionPolicy: .excludeTokenUTXOs,
                    reuseMatchingReservation: false,
                    mapReservationError: { Error.tokenSelectionFailed($0) }
                )
                let reservedPayerHandle = SpendReservation(addressBook: fundingBook, reservation: payerReservation.reservation)
                payerHandle = reservedPayerHandle
                try Task.checkCancellation()
                var combinedSigningKeys = tokenReservation.signingKeys
                for (input, key) in payerReservation.signingKeys {
                    guard combinedSigningKeys.updateValue(key, forKey: input) == nil else {
                        throw Error.tokenSelectionFailed(OpalBase.Address.Book.Error.utxoDuplicated(input))
                    }
                }
                reservationHandles = [tokenHandle, reservedPayerHandle]
                signingKeys = combinedSigningKeys
                reservedTokenChangeEntry = tokenReservation.reservedChangeEntry
                reservedBCHChangeEntry = payerReservation.reservedChangeEntry
                bchChangeOutput = OpalBase.Transaction.Output(
                    value: changeAmount.uint64,
                    address: payerReservation.reservedChangeEntry.address
                )
            } catch {
                let preparationError = error
                var cleanupError: Swift.Error?
                if let payerHandle {
                    do { try await payerHandle.cancel() }
                    catch { cleanupError = error }
                }
                do { try await tokenHandle.cancel() }
                catch { if cleanupError == nil { cleanupError = error } }
                if let cleanupError { throw Error.transactionBuildFailed(cleanupError) }
                throw preparationError
            }
        } else {
            let context = try await reserveSpendContext(
                inputs: inputs,
                outputs: organizedTokenOutputs,
                changeEntry: bchChangeEntry,
                tokenSelectionPolicy: .allowTokenUTXOs,
                reuseMatchingReservation: false,
                mapReservationError: { Error.tokenSelectionFailed($0) },
                mapInsufficientFundsError: Error.transactionBuildFailed(OpalBase.Satoshi.Error.negativeResult),
                beforeReservation: beforeReservation
            )
            reservationHandles = [context.reservationHandle]
            signingKeys = context.signingKeys
            reservedTokenChangeEntry = context.changeEntry
            reservedBCHChangeEntry = context.changeEntry
            bchChangeOutput = context.changeOutput
        }

        do {
            try Task.checkCancellation()
            let resolvedTokenChangeOutputs: [OpalBase.Transaction.Output]
            let resolvedTokenOwnerBCHChangeOutput: OpalBase.Transaction.Output?
            let resolvedOrganizedTokenOutputs: [OpalBase.Transaction.Output]
            let reservedTokenChangeAddress = try makeTokenAwareAddress(for: reservedTokenChangeEntry)
            if reservedTokenChangeAddress == tokenChangeAddress {
                resolvedTokenChangeOutputs = tokenChangeOutputs
            } else {
                resolvedTokenChangeOutputs = tokenChangeOutputs.map { output in
                    makeRetargetedOutput(output, for: reservedTokenChangeAddress)
                }
            }
            if let tokenOwnerBCHChangeOutput,
               reservedTokenChangeEntry.address != tokenChangeEntry.address {
                resolvedTokenOwnerBCHChangeOutput = makeRetargetedOutput(
                    tokenOwnerBCHChangeOutput,
                    for: reservedTokenChangeEntry.address
                )
            } else {
                resolvedTokenOwnerBCHChangeOutput = tokenOwnerBCHChangeOutput
            }
            let originalChangeOutputs = tokenChangeOutputs + [tokenOwnerBCHChangeOutput].compactMap { $0 }
            let resolvedChangeOutputs = resolvedTokenChangeOutputs + [resolvedTokenOwnerBCHChangeOutput].compactMap { $0 }
            resolvedOrganizedTokenOutputs = replacePlannedOutputs(
                in: organizedTokenOutputs,
                originals: originalChangeOutputs,
                replacements: resolvedChangeOutputs
            )

            return TokenSpendPlan(transfer: transfer,
                                  tokenAccountIndex: unhardenedIndex,
                                  bchFundingAccountIndex: await fundingAccount.unhardenedIndex,
                                  feeRate: feeRate,
                                  tokenInputs: selectedTokenInputs,
                                  bchInputs: bchInputs,
                                  tokenRecipientOutputs: rawRecipientOutputs,
                                  tokenChangeOutputs: resolvedTokenChangeOutputs,
                                  tokenOwnerBCHChangeOutput: resolvedTokenOwnerBCHChangeOutput,
                                  bchChangeOutput: bchChangeOutput,
                                  shouldAllowDustDonation: transfer.shouldAllowDustDonation,
                                  reservationHandles: reservationHandles,
                                  tokenOwnerChangeEntry: reservedTokenChangeEntry,
                                  bchChangeEntry: reservedBCHChangeEntry,
                                  signingKeys: signingKeys,
                                  organizedTokenOutputs: resolvedOrganizedTokenOutputs,
                                  shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
        } catch {
            let preparationError = error
            var cleanupError: Swift.Error?
            for handle in reservationHandles {
                do { try await handle.cancel() }
                catch { if cleanupError == nil { cleanupError = error } }
            }
            if let cleanupError { throw Error.transactionBuildFailed(cleanupError) }
            throw preparationError
        }
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
