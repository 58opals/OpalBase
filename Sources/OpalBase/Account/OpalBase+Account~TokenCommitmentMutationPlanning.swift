// OpalBase+Account~TokenCommitmentMutationPlanning.swift

import Foundation

extension _OpalBase.Account {
    public func prepareTokenCommitmentMutation(
        _ mutation: TokenCommitmentMutation,
        feePolicy: OpalBase.Wallet.FeePolicy = .init()
    ) async throws -> TokenCommitmentMutationPlan {
        try await prepareTokenCommitmentMutation(
            mutation,
            feePolicy: feePolicy,
            beforeReservation: nil
        )
    }

    func prepareTokenCommitmentMutation(
        _ mutation: TokenCommitmentMutation,
        feePolicy: OpalBase.Wallet.FeePolicy = .init(),
        beforeReservation: (@Sendable (OpalBase.Address.Book.Entry) async throws -> Void)?
    ) async throws -> TokenCommitmentMutationPlan {
        try requirePrivateKeyMaterial()

        let spendableOutputs = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        let authorityInput: OpalBase.Transaction.Output.Unspent
        switch mutation.target {
        case .preferredInput(let preferredInput):
            guard let storedAuthorityInput = spendableOutputs.first(where: { $0 == preferredInput }) else {
                throw Error.tokenMutationInvalidAuthorityInput
            }
            authorityInput = storedAuthorityInput
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
              let authorityNonFungibleToken = authorityTokenData.nft,
              authorityNonFungibleToken.capability == .mutable
                || authorityNonFungibleToken.capability == .minting else {
            throw Error.tokenMutationInvalidAuthorityInput
        }
        
        let newNonFungibleToken: OpalBase.CashTokens.NFT
        do {
            newNonFungibleToken = try OpalBase.CashTokens.NFT(capability: authorityNonFungibleToken.capability,
                                                     commitment: mutation.newCommitment)
        } catch {
            throw Error.tokenMutationInvalidAuthorityInput
        }
        
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        let tokenChangeAddress = try makeTokenAwareAddress(for: changeEntry)
        
        let destinationIsExternal = await !addressBook.contains(address: mutation.destination)
        let attachedFungibleAmount = authorityTokenData.amount
        let mutatedTokenData: OpalBase.CashTokens.TokenData
        var fungiblePreservationOutput: OpalBase.Transaction.Output?
        
        if destinationIsExternal && mutation.shouldPreserveAttachedFungibleToWallet {
            mutatedTokenData = OpalBase.CashTokens.TokenData(category: authorityTokenData.category,
                                                    amount: nil,
                                                    nft: newNonFungibleToken)
            if let attachedFungibleAmount, attachedFungibleAmount > 0 {
                let fungibleTokenData = OpalBase.CashTokens.TokenData(category: authorityTokenData.category,
                                                             amount: attachedFungibleAmount,
                                                             nft: nil)
                fungiblePreservationOutput = try makeTokenOutput(
                    address: tokenChangeAddress,
                    tokenData: fungibleTokenData,
                    mapDustError: { Error.tokenMutationCannotComputeDustThreshold($0) }
                )
            }
        } else {
            mutatedTokenData = OpalBase.CashTokens.TokenData(category: authorityTokenData.category,
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
        for output in plannedTokenOutputs {
            let dustThreshold = try output.calculateDustThreshold(feeRate: OpalBase.Transaction.minimumRelayFeeRate)
            guard output.value >= dustThreshold else {
                throw Error.transactionBuildFailed(OpalBase.Transaction.Error.outputValueIsLessThanTheDustLimit)
            }
        }
        let organizedTokenOutputs = try await privacyShaper.organizeOutputs(plannedTokenOutputs)
        
        let feeRate = feePolicy.recommendFeeRate(for: mutation.feeContext, override: mutation.feeOverride)
        let bchInputs = try selectBCHInputs(from: spendableOutputs,
                                                            existingInputs: [authorityInput],
                                                            outputs: organizedTokenOutputs,
                                                            feeRate: feeRate,
                                                            shouldAllowDustDonation: mutation.shouldAllowDustDonation,
                                                            changeLockingScript: changeEntry.address.lockingScript.data)
        
        let inputs = [authorityInput] + bchInputs
        let reservedSpendContext = try await reserveSpendContext(
            inputs: inputs,
            outputs: organizedTokenOutputs,
            changeEntry: changeEntry,
            tokenSelectionPolicy: .allowTokenUTXOs,
            mapReservationError: { Error.tokenSelectionFailed($0) },
            mapInsufficientFundsError: Error.transactionBuildFailed(OpalBase.Satoshi.Error.negativeResult),
            beforeReservation: beforeReservation
        )

        let resolvedFungiblePreservationOutput: OpalBase.Transaction.Output?
        let resolvedOrganizedTokenOutputs: [OpalBase.Transaction.Output]
        let reservedTokenChangeAddress = try makeTokenAwareAddress(for: reservedSpendContext.changeEntry)
        if let fungiblePreservationOutput, reservedTokenChangeAddress != tokenChangeAddress {
            let retargetedFungiblePreservationOutput = makeRetargetedOutput(
                fungiblePreservationOutput,
                for: reservedTokenChangeAddress
            )
            resolvedFungiblePreservationOutput = retargetedFungiblePreservationOutput
            resolvedOrganizedTokenOutputs = replacePlannedOutputs(
                in: organizedTokenOutputs,
                originals: [fungiblePreservationOutput],
                replacements: [retargetedFungiblePreservationOutput]
            )
        } else {
            resolvedFungiblePreservationOutput = fungiblePreservationOutput
            resolvedOrganizedTokenOutputs = organizedTokenOutputs
        }
        
        return TokenCommitmentMutationPlan(mutation: mutation,
                                           feeRate: feeRate,
                                           authorityInput: authorityInput,
                                           bchInputs: bchInputs,
                                           mutatedTokenOutput: mutatedTokenOutput,
                                           fungiblePreservationOutput: resolvedFungiblePreservationOutput,
                                           bchChangeOutput: reservedSpendContext.changeOutput,
                                           shouldAllowDustDonation: mutation.shouldAllowDustDonation,
                                           reservationHandle: reservedSpendContext.reservationHandle,
                                           signingKeys: reservedSpendContext.signingKeys,
                                           organizedTokenOutputs: resolvedOrganizedTokenOutputs,
                                           shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }
}
