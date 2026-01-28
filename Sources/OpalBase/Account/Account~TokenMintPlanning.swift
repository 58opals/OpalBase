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
            let spendableSet = Set(spendableOutputs)
            guard spendableSet.contains(preferredMintingInput),
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
        
        let requiredFungibleOut = try mint.recipients.reduce(0) { result, recipient in
            let recipientAmount = recipient.fungibleAmount ?? 0
            return Int(try addOrThrow(UInt64(result), recipientAmount))
        }
        let authorityFungibleIn = authorityInput.tokenData?.amount ?? 0
        
        var extraFungibleInputs: [Transaction.Output.Unspent] = .init()
        var totalSelectedFungible = authorityFungibleIn
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
                totalSelectedFungible = try addOrThrow(totalSelectedFungible, amount)
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
        
        let minimumRelayFeeRate = Transaction.minimumRelayFeeRate
        func makeTokenOutput(address: Address,
                             tokenData: CashTokens.TokenData,
                             overrideAmount: Satoshi? = nil) throws -> Transaction.Output {
            let outputTemplate = Transaction.Output(value: 0,
                                                    address: address,
                                                    tokenData: tokenData)
            let dustThreshold: UInt64
            do {
                dustThreshold = try outputTemplate.dustThreshold(feeRate: minimumRelayFeeRate)
            } catch {
                throw Error.transactionBuildFailed(error)
            }
            let outputValue = overrideAmount?.uint64 ?? dustThreshold
            return Transaction.Output(value: outputValue,
                                      address: address,
                                      tokenData: tokenData)
        }
        
        let tokenRecipientOutputs = try mint.recipients.map { recipient in
            let tokenData = CashTokens.TokenData(category: mint.category,
                                                 amount: recipient.fungibleAmount,
                                                 nft: recipient.nft)
            return try makeTokenOutput(address: recipient.address,
                                       tokenData: tokenData,
                                       overrideAmount: recipient.bchAmount)
        }
        
        let selectedTokenInputs = [authorityInput] + extraFungibleInputs
        let totalFungibleIn = try selectedTokenInputs.reduce(0) { result, output in
            let amount = output.tokenData?.amount ?? 0
            return Int(try addOrThrow(UInt64(result), amount))
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
                                                      amount: UInt64(preservedFungible) > 0 ? UInt64(preservedFungible) : nil,
                                                      nft: authorityNonFungibleToken)
            authorityReturnOutput = try makeTokenOutput(address: tokenChangeAddress,
                                                        tokenData: authorityToken)
        case .toAddress(let address, let bitcoinCashAmount):
            let authorityToken = CashTokens.TokenData(category: mint.category,
                                                      amount: nil,
                                                      nft: authorityNonFungibleToken)
            authorityReturnOutput = try makeTokenOutput(address: address,
                                                        tokenData: authorityToken,
                                                        overrideAmount: bitcoinCashAmount)
            if preservedFungible > 0 {
                let fungibleToken = CashTokens.TokenData(category: mint.category,
                                                         amount: UInt64(preservedFungible),
                                                         nft: nil)
                fungiblePreservationOutput = try makeTokenOutput(address: tokenChangeAddress,
                                                                 tokenData: fungibleToken)
            }
        case .burn:
            if preservedFungible > 0 {
                let fungibleToken = CashTokens.TokenData(category: mint.category,
                                                         amount: UInt64(preservedFungible),
                                                         nft: nil)
                fungiblePreservationOutput = try makeTokenOutput(address: tokenChangeAddress,
                                                                 tokenData: fungibleToken)
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
        
        return TokenMintPlan(mint: mint,
                             feeRate: feeRate,
                             authorityInput: authorityInput,
                             extraFungibleInputs: extraFungibleInputs,
                             bitcoinCashInputs: bitcoinCashInputs,
                             tokenRecipientOutputs: tokenRecipientOutputs,
                             authorityReturnOutput: authorityReturnOutput,
                             fungiblePreservationOutput: fungiblePreservationOutput,
                             bitcoinCashChangeOutput: changeOutput,
                             shouldAllowDustDonation: mint.shouldAllowDustDonation,
                             addressBook: addressBook,
                             changeEntry: reservation.changeEntry,
                             reservation: reservation,
                             privateKeys: privateKeys,
                             organizedTokenOutputs: organizedTokenOutputs,
                             shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }
}
