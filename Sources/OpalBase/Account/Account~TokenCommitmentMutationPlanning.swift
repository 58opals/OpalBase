//  Account~TokenCommitmentMutationPlanning.swift

import Foundation

extension Account {
    public func prepareTokenCommitmentMutation(
        _ mutation: TokenCommitmentMutation,
        feePolicy: Wallet.FeePolicy = .init()
    ) async throws -> TokenCommitmentMutationPlan {
        let spendableOutputs = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        let authorityInput: Transaction.Output.Unspent
        switch mutation.target {
        case .preferredInput(let preferredInput):
            guard spendableOutputs.contains(preferredInput) else {
                throw Error.tokenMutationInvalidAuthorityInput
            }
            authorityInput = preferredInput
        case .byGroup(let group):
            guard let selectedAuthorityInput = spendableOutputs.first(where: { output in
                guard let tokenData = output.tokenData,
                      let nonFungibleToken = tokenData.nft else {
                    return false
                }
                return tokenData.category == group.category
                && nonFungibleToken.commitment == group.commitment
                && nonFungibleToken.capability == group.capability
            }) else {
                throw Error.tokenMutationNoEligibleAuthorityInput
            }
            authorityInput = selectedAuthorityInput
        }
        
        guard let authorityTokenData = authorityInput.tokenData,
              let authorityNonFungibleToken = authorityTokenData.nft else {
            throw Error.tokenMutationInvalidAuthorityInput
        }
        guard authorityNonFungibleToken.capability == .mutable
                || authorityNonFungibleToken.capability == .minting else {
            throw Error.tokenMutationInvalidAuthorityInput
        }
        
        let newNonFungibleToken: CashTokens.NFT
        do {
            newNonFungibleToken = try CashTokens.NFT(capability: authorityNonFungibleToken.capability,
                                                     commitment: mutation.newCommitment)
        } catch {
            throw Error.tokenMutationInvalidAuthorityInput
        }
        
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        let tokenChangeAddress = try Address(script: changeEntry.address.lockingScript, format: .tokenAware)
        
        let destinationIsExternal = await !addressBook.contains(address: mutation.destination)
        let attachedFungibleAmount = authorityTokenData.amount
        let mutatedTokenData: CashTokens.TokenData
        var fungiblePreservationOutput: Transaction.Output?
        
        if destinationIsExternal && mutation.preserveAttachedFungibleToWallet {
            mutatedTokenData = CashTokens.TokenData(category: authorityTokenData.category,
                                                    amount: nil,
                                                    nft: newNonFungibleToken)
            if let attachedFungibleAmount, attachedFungibleAmount > 0 {
                let fungibleTokenData = CashTokens.TokenData(category: authorityTokenData.category,
                                                             amount: attachedFungibleAmount,
                                                             nft: nil)
                fungiblePreservationOutput = try makeTokenOutput(
                    address: tokenChangeAddress,
                    tokenData: fungibleTokenData,
                    mapDustError: { Error.tokenMutationCannotComputeDustThreshold($0) }
                )
            }
        } else {
            mutatedTokenData = CashTokens.TokenData(category: authorityTokenData.category,
                                                    amount: attachedFungibleAmount,
                                                    nft: newNonFungibleToken)
        }
        
        let mutatedTokenOutput = try makeTokenOutput(
            address: mutation.destination,
            tokenData: mutatedTokenData,
            overrideAmount: mutation.bchAmount,
            mapDustError: { Error.tokenMutationCannotComputeDustThreshold($0) }
        )
        let plannedTokenOutputs = [mutatedTokenOutput, fungiblePreservationOutput].compactMap { $0 }
        let organizedTokenOutputs = await privacyShaper.organizeOutputs(plannedTokenOutputs)
        
        let feeRate = feePolicy.recommendFeeRate(for: mutation.feeContext, override: mutation.feeOverride)
        let bitcoinCashInputs = try selectBitcoinCashInputs(from: spendableOutputs,
                                                            existingInputs: [authorityInput],
                                                            outputs: organizedTokenOutputs,
                                                            feeRate: feeRate,
                                                            shouldAllowDustDonation: mutation.shouldAllowDustDonation,
                                                            changeLockingScript: changeEntry.address.lockingScript.data)
        
        let inputs = [authorityInput] + bitcoinCashInputs
        let reservedSpendContext = try await reserveSpendContext(
            inputs: inputs,
            outputs: organizedTokenOutputs,
            changeEntry: changeEntry,
            tokenSelectionPolicy: .allowTokenUTXOs,
            mapReservationError: { Error.tokenSelectionFailed($0) },
            mapInsufficientFundsError: Error.transactionBuildFailed(Satoshi.Error.negativeResult)
        )
        
        return TokenCommitmentMutationPlan(mutation: mutation,
                                           feeRate: feeRate,
                                           authorityInput: authorityInput,
                                           bitcoinCashInputs: bitcoinCashInputs,
                                           mutatedTokenOutput: mutatedTokenOutput,
                                           fungiblePreservationOutput: fungiblePreservationOutput,
                                           bitcoinCashChangeOutput: reservedSpendContext.changeOutput,
                                           shouldAllowDustDonation: mutation.shouldAllowDustDonation,
                                           reservationHandle: reservedSpendContext.reservationHandle,
                                           privateKeys: reservedSpendContext.privateKeys,
                                           organizedTokenOutputs: organizedTokenOutputs,
                                           shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }
}
