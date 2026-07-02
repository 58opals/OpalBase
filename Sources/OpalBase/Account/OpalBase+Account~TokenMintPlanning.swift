// OpalBase+Account~TokenMintPlanning.swift

import Foundation

extension _OpalBase.Account {
    public func prepareTokenMint(
        _ mint: TokenMint,
        preferredMintingInput: OpalBase.Transaction.Output.Unspent? = nil,
        feePolicy: OpalBase.Wallet.FeePolicy = .init()
    ) async throws -> TokenMintPlan {
        try await prepareTokenMint(
            mint,
            preferredMintingInput: preferredMintingInput,
            feePolicy: feePolicy,
            beforeReservation: nil
        )
    }

    func prepareTokenMint(
        _ mint: TokenMint,
        preferredMintingInput: OpalBase.Transaction.Output.Unspent? = nil,
        feePolicy: OpalBase.Wallet.FeePolicy = .init(),
        beforeReservation: (@Sendable (OpalBase.Address.Book.Entry) async throws -> Void)?
    ) async throws -> TokenMintPlan {
        try requirePrivateKeyMaterial()

        let spendableOutputs = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        func isMintingAuthorityInput(_ output: OpalBase.Transaction.Output.Unspent) -> Bool {
            guard let tokenData = output.tokenData else { return false }
            return tokenData.category == mint.category
                && tokenData.nft?.capability == .minting
        }

        let authorityInput: OpalBase.Transaction.Output.Unspent
        if let preferredMintingInput {
            guard let spendableMintingInput = spendableOutputs.first(where: { $0 == preferredMintingInput }),
                  isMintingAuthorityInput(spendableMintingInput) else {
                throw Error.tokenMintNoEligibleMintingInput
            }
            authorityInput = spendableMintingInput
        } else {
            guard let selectedAuthorityInput = spendableOutputs.first(where: isMintingAuthorityInput) else {
                throw Error.tokenMintNoEligibleMintingInput
            }
            authorityInput = selectedAuthorityInput
        }
        
        let requiredFungibleOut: UInt64 = try mint.recipients.reduce(UInt64(0)) { total, recipient in
            try total.addOrThrow(recipient.fungibleAmount ?? 0,
                                 overflowError: Error.paymentExceedsMaximumAmount)
        }
        let authorityFungibleIn: UInt64 = authorityInput.tokenData?.amount ?? 0
        
        var extraFungibleInputs: [OpalBase.Transaction.Output.Unspent] = .init()
        var totalSelectedFungible: UInt64 = authorityFungibleIn
        if requiredFungibleOut > authorityFungibleIn {
            let fungibleCandidates = spendableOutputs
                .filter { output in
                    guard output != authorityInput else { return false }
                    guard let tokenData = output.tokenData else { return false }
                    return tokenData.category == mint.category
                    && tokenData.nft == nil
                    && tokenData.amount != nil
                }
                .sorted { left, right in
                    (left.tokenData?.amount ?? 0) > (right.tokenData?.amount ?? 0)
                }
            
            for candidate in fungibleCandidates {
                extraFungibleInputs.append(candidate)
                let amount = candidate.tokenData?.amount ?? 0
                totalSelectedFungible = try totalSelectedFungible.addOrThrow(
                    amount,
                    overflowError: Error.paymentExceedsMaximumAmount
                )
                if totalSelectedFungible >= requiredFungibleOut {
                    break
                }
            }
            
            guard totalSelectedFungible >= requiredFungibleOut else {
                throw Error.tokenMintInsufficientFungible
            }
        }
        
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        let tokenChangeAddress = try makeTokenAwareAddress(for: changeEntry)
        
        let tokenRecipientOutputs = try mint.recipients.map { recipient in
            let tokenData = OpalBase.CashTokens.TokenData(category: mint.category,
                                                 amount: recipient.fungibleAmount,
                                                 nft: recipient.nft)
            return try makeTokenOutput(
                address: recipient.address,
                tokenData: tokenData,
                overrideAmount: recipient.bchAmount,
                mapDustError: { Error.transactionBuildFailed($0) }
            )
        }
        
        let selectedTokenInputs = [authorityInput] + extraFungibleInputs
        let totalFungibleIn: UInt64 = try selectedTokenInputs.reduce(UInt64(0)) { total, output in
            try total.addOrThrow(output.tokenData?.amount ?? 0,
                                 overflowError: Error.paymentExceedsMaximumAmount)
        }
        guard totalFungibleIn >= requiredFungibleOut else {
            throw Error.tokenMintInsufficientFungible
        }
        let preservedFungible = totalFungibleIn - requiredFungibleOut
        
        guard let authorityNonFungibleToken = authorityInput.tokenData?.nft else {
            throw Error.tokenMintNoEligibleMintingInput
        }
        
        var authorityReturnOutput: OpalBase.Transaction.Output?
        var authorityReturnUsesWalletChange = false
        var fungiblePreservationOutput: OpalBase.Transaction.Output?
        var fungiblePreservationUsesWalletChange = false
        switch mint.authorityReturn {
        case .toWalletChange:
            authorityReturnUsesWalletChange = true
            
            let authorityToken = OpalBase.CashTokens.TokenData(category: mint.category,
                                                      amount: preservedFungible > 0 ? preservedFungible : nil,
                                                      nft: authorityNonFungibleToken)
            authorityReturnOutput = try makeTokenOutput(
                address: tokenChangeAddress,
                tokenData: authorityToken,
                mapDustError: { Error.transactionBuildFailed($0) }
            )
        case .toAddress(let address, let bitcoinCashAmount):
            let authorityToken = OpalBase.CashTokens.TokenData(category: mint.category,
                                                      amount: nil,
                                                      nft: authorityNonFungibleToken)
            authorityReturnOutput = try makeTokenOutput(
                address: address,
                tokenData: authorityToken,
                overrideAmount: bitcoinCashAmount,
                mapDustError: { Error.transactionBuildFailed($0) }
            )
            if preservedFungible > 0 {
                fungiblePreservationUsesWalletChange = true
                let fungibleToken = OpalBase.CashTokens.TokenData(category: mint.category,
                                                         amount: preservedFungible,
                                                         nft: nil)
                fungiblePreservationOutput = try makeTokenOutput(
                    address: tokenChangeAddress,
                    tokenData: fungibleToken,
                    mapDustError: { Error.transactionBuildFailed($0) }
                )
            }
        case .burn:
            if preservedFungible > 0 {
                fungiblePreservationUsesWalletChange = true
                let fungibleToken = OpalBase.CashTokens.TokenData(category: mint.category,
                                                         amount: preservedFungible,
                                                         nft: nil)
                fungiblePreservationOutput = try makeTokenOutput(
                    address: tokenChangeAddress,
                    tokenData: fungibleToken,
                    mapDustError: { Error.transactionBuildFailed($0) }
                )
            }
        }
        
        let plannedTokenOutputs = tokenRecipientOutputs
        + [authorityReturnOutput, fungiblePreservationOutput].compactMap { $0 }
        for output in plannedTokenOutputs {
            let dustThreshold = try output.calculateDustThreshold(feeRate: OpalBase.Transaction.minimumRelayFeeRate)
            guard output.value >= dustThreshold else {
                throw Error.transactionBuildFailed(OpalBase.Transaction.Error.outputValueIsLessThanTheDustLimit)
            }
        }
        let organizedTokenOutputs = try await privacyShaper.organizeOutputs(plannedTokenOutputs)
        
        let feeRate = feePolicy.recommendFeeRate(for: mint.feeContext, override: mint.feeOverride)
        let bchInputs = try selectBCHInputs(from: spendableOutputs,
                                                            existingInputs: selectedTokenInputs,
                                                            outputs: organizedTokenOutputs,
                                                            feeRate: feeRate,
                                                            shouldAllowDustDonation: mint.shouldAllowDustDonation,
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

        let resolvedAuthorityReturnOutput: OpalBase.Transaction.Output?
        let resolvedFungiblePreservationOutput: OpalBase.Transaction.Output?
        let resolvedOrganizedTokenOutputs: [OpalBase.Transaction.Output]
        let reservedTokenChangeAddress = try makeTokenAwareAddress(for: reservedSpendContext.changeEntry)
        if reservedTokenChangeAddress == tokenChangeAddress {
            resolvedAuthorityReturnOutput = authorityReturnOutput
            resolvedFungiblePreservationOutput = fungiblePreservationOutput
            resolvedOrganizedTokenOutputs = organizedTokenOutputs
        } else {
            resolvedAuthorityReturnOutput = authorityReturnUsesWalletChange
            ? authorityReturnOutput.map { makeRetargetedOutput($0, for: reservedTokenChangeAddress) }
            : authorityReturnOutput
            resolvedFungiblePreservationOutput = fungiblePreservationUsesWalletChange
            ? fungiblePreservationOutput.map { makeRetargetedOutput($0, for: reservedTokenChangeAddress) }
            : fungiblePreservationOutput

            let originalWalletOutputs = [
                authorityReturnUsesWalletChange ? authorityReturnOutput : nil,
                fungiblePreservationUsesWalletChange ? fungiblePreservationOutput : nil
            ].compactMap { $0 }
            let resolvedWalletOutputs = [
                authorityReturnUsesWalletChange ? resolvedAuthorityReturnOutput : nil,
                fungiblePreservationUsesWalletChange ? resolvedFungiblePreservationOutput : nil
            ].compactMap { $0 }
            resolvedOrganizedTokenOutputs = replacePlannedOutputs(
                in: organizedTokenOutputs,
                originals: originalWalletOutputs,
                replacements: resolvedWalletOutputs
            )
        }
        
        return TokenMintPlan(mint: mint,
                             feeRate: feeRate,
                             authorityInput: authorityInput,
                             extraFungibleInputs: extraFungibleInputs,
                             bchInputs: bchInputs,
                             tokenRecipientOutputs: tokenRecipientOutputs,
                             authorityReturnOutput: resolvedAuthorityReturnOutput,
                             fungiblePreservationOutput: resolvedFungiblePreservationOutput,
                             bchChangeOutput: reservedSpendContext.changeOutput,
                             shouldAllowDustDonation: mint.shouldAllowDustDonation,
                             reservationHandle: reservedSpendContext.reservationHandle,
                             signingKeys: reservedSpendContext.signingKeys,
                             organizedTokenOutputs: resolvedOrganizedTokenOutputs,
                             shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }
}
