// Account~TokenMintPlanning.swift

import Foundation

extension Account {
    public func prepareTokenMint(
        _ mint: TokenMint,
        preferredMintingInput: Transaction.Output.Unspent? = nil,
        feePolicy: Wallet.FeePolicy = .init()
    ) async throws -> TokenMintPlan {
        let spendableOutputs = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        let authorityInput: Transaction.Output.Unspent
        if let preferredMintingInput {
            guard spendableOutputs.contains(preferredMintingInput),
                  let tokenData = preferredMintingInput.tokenData,
                  tokenData.category == mint.category,
                  tokenData.nft?.capability == .minting else {
                throw Error.tokenMintNoEligibleMintingInput
            }
            authorityInput = preferredMintingInput
        } else {
            guard let selectedAuthorityInput = spendableOutputs.first(where: { output in
                guard let tokenData = output.tokenData else { return false }
                return tokenData.category == mint.category
                && tokenData.nft?.capability == .minting
            }) else {
                throw Error.tokenMintNoEligibleMintingInput
            }
            authorityInput = selectedAuthorityInput
        }
        
        let requiredFungibleOut: UInt64 = try mint.recipients.reduce(UInt64(0)) { total, recipient in
            try total.addOrThrow(recipient.fungibleAmount ?? 0,
                                 overflowError: Error.paymentExceedsMaximumAmount)
        }
        let authorityFungibleIn: UInt64 = authorityInput.tokenData?.amount ?? 0
        
        var extraFungibleInputs: [Transaction.Output.Unspent] = .init()
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
        let tokenChangeAddress = try Address(script: changeEntry.address.lockingScript, format: .tokenAware)
        
        let tokenRecipientOutputs = try mint.recipients.map { recipient in
            let tokenData = CashTokens.TokenData(category: mint.category,
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
        
        guard let authorityTokenData = authorityInput.tokenData,
              let authorityNonFungibleToken = authorityTokenData.nft else {
            throw Error.tokenMintNoEligibleMintingInput
        }
        
        var authorityReturnOutput: Transaction.Output?
        var fungiblePreservationOutput: Transaction.Output?
        switch mint.authorityReturn {
        case .toWalletChange:
            
            let authorityToken = CashTokens.TokenData(category: mint.category,
                                                      amount: preservedFungible > 0 ? preservedFungible : nil,
                                                      nft: authorityNonFungibleToken)
            authorityReturnOutput = try makeTokenOutput(
                address: tokenChangeAddress,
                tokenData: authorityToken,
                mapDustError: { Error.transactionBuildFailed($0) }
            )
        case .toAddress(let address, let bitcoinCashAmount):
            let authorityToken = CashTokens.TokenData(category: mint.category,
                                                      amount: nil,
                                                      nft: authorityNonFungibleToken)
            authorityReturnOutput = try makeTokenOutput(
                address: address,
                tokenData: authorityToken,
                overrideAmount: bitcoinCashAmount,
                mapDustError: { Error.transactionBuildFailed($0) }
            )
            if preservedFungible > 0 {
                let fungibleToken = CashTokens.TokenData(category: mint.category,
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
                let fungibleToken = CashTokens.TokenData(category: mint.category,
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
        let organizedTokenOutputs = await privacyShaper.organizeOutputs(plannedTokenOutputs)
        
        let feeRate = feePolicy.recommendFeeRate(for: mint.feeContext, override: mint.feeOverride)
        let bitcoinCashInputs = try selectBitcoinCashInputs(from: spendableOutputs,
                                                            existingInputs: selectedTokenInputs,
                                                            outputs: organizedTokenOutputs,
                                                            feeRate: feeRate,
                                                            shouldAllowDustDonation: mint.shouldAllowDustDonation,
                                                            changeLockingScript: changeEntry.address.lockingScript.data)
        
        let inputs = selectedTokenInputs + bitcoinCashInputs
        let reservedSpendContext = try await reserveSpendContext(
            inputs: inputs,
            outputs: organizedTokenOutputs,
            changeEntry: changeEntry,
            tokenSelectionPolicy: .allowTokenUTXOs,
            mapReservationError: { Error.tokenSelectionFailed($0) },
            mapInsufficientFundsError: Error.transactionBuildFailed(Satoshi.Error.negativeResult)
        )
        
        return TokenMintPlan(mint: mint,
                             feeRate: feeRate,
                             authorityInput: authorityInput,
                             extraFungibleInputs: extraFungibleInputs,
                             bitcoinCashInputs: bitcoinCashInputs,
                             tokenRecipientOutputs: tokenRecipientOutputs,
                             authorityReturnOutput: authorityReturnOutput,
                             fungiblePreservationOutput: fungiblePreservationOutput,
                             bitcoinCashChangeOutput: reservedSpendContext.changeOutput,
                             shouldAllowDustDonation: mint.shouldAllowDustDonation,
                             reservationHandle: reservedSpendContext.reservationHandle,
                             privateKeys: reservedSpendContext.privateKeys,
                             organizedTokenOutputs: organizedTokenOutputs,
                             shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }
}
