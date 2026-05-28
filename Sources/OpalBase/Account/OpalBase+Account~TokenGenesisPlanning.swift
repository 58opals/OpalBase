// OpalBase+Account~TokenGenesisPlanning.swift

import Foundation

extension _OpalBase.Account {
    public func prepareTokenGenesis(
        _ genesis: TokenGenesis,
        preferredGenesisInput: OpalBase.Transaction.Output.Unspent? = nil,
        feePolicy: OpalBase.Wallet.FeePolicy = .init()
    ) async throws -> TokenGenesisPlan {
        try await prepareTokenGenesis(
            genesis,
            preferredGenesisInput: preferredGenesisInput,
            feePolicy: feePolicy,
            beforeReservation: nil
        )
    }

    func prepareTokenGenesis(
        _ genesis: TokenGenesis,
        preferredGenesisInput: OpalBase.Transaction.Output.Unspent? = nil,
        feePolicy: OpalBase.Wallet.FeePolicy = .init(),
        beforeReservation: (@Sendable (OpalBase.Address.Book.Entry) async throws -> Void)?
    ) async throws -> TokenGenesisPlan {
        guard !genesis.recipients.isEmpty || genesis.reservedSupplyToSelf != nil else {
            throw Error.tokenGenesisHasNoRecipients
        }
        
        let unsafeRecipients = genesis.recipients.filter { !$0.address.isTokenAware }
        if !unsafeRecipients.isEmpty {
            throw Error.tokenGenesisRequiresTokenAwareAddress(unsafeRecipients.map(\.address))
        }
        
        let spendableOutputs = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        let genesisInput: OpalBase.Transaction.Output.Unspent
        if let preferredGenesisInput {
            guard let spendableGenesisInput = spendableOutputs.first(where: { $0 == preferredGenesisInput }),
                  spendableGenesisInput.tokenData == nil,
                  spendableGenesisInput.previousTransactionOutputIndex == 0 else {
                throw Error.tokenGenesisInvalidGenesisInput
            }
            genesisInput = spendableGenesisInput
        } else {
            guard let selectedGenesisInput = selectGenesisInput(from: spendableOutputs) else {
                // Consider calling prepareTokenGenesisOutpoint to identify a valid genesis input.
                throw Error.tokenGenesisNoEligibleGenesisInput
            }
            genesisInput = selectedGenesisInput
        }
        
        let category: OpalBase.CashTokens.CategoryID
        do {
            category = try OpalBase.CashTokens.CategoryID(transactionOrderData: genesisInput.previousTransactionHash.naturalOrder)
        } catch {
            throw Error.tokenGenesisInvalidGenesisInput
        }
        
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        let tokenChangeAddress = try makeTokenAwareAddress(for: changeEntry)
        var rawOutputs: [OpalBase.Transaction.Output] = .init()
        var walletReservedSupplyOutput: OpalBase.Transaction.Output?
        for recipient in genesis.recipients {
            let tokenData = OpalBase.CashTokens.TokenData(category: category,
                                                 amount: recipient.fungibleAmount,
                                                 nft: recipient.nft)
            let dustOutput = try makeTokenOutput(
                address: recipient.address,
                tokenData: tokenData,
                mapDustError: { Error.tokenGenesisCannotComputeDustThreshold($0) }
            )
            if let bchAmount = recipient.bchAmount {
                guard bchAmount.uint64 >= dustOutput.value else {
                    throw Error.tokenGenesisInvalidGenesisInput
                }
                rawOutputs.append(try makeTokenOutput(
                    address: recipient.address,
                    tokenData: tokenData,
                    overrideAmount: bchAmount,
                    mapDustError: { Error.tokenGenesisCannotComputeDustThreshold($0) }
                ))
            } else {
                rawOutputs.append(dustOutput)
            }
        }
        
        if let reservedSupply = genesis.reservedSupplyToSelf {
            let mintingToken: OpalBase.CashTokens.NFT?
            if reservedSupply.shouldIncludeMintingNonFungibleToken {
                do {
                    mintingToken = try OpalBase.CashTokens.NFT(capability: .minting,
                                                      commitment: reservedSupply.commitment)
                } catch {
                    throw Error.tokenGenesisInvalidGenesisInput
                }
            } else {
                mintingToken = nil
            }
            let tokenData = OpalBase.CashTokens.TokenData(category: category,
                                                 amount: reservedSupply.fungibleAmount,
                                                 nft: mintingToken)
            let reservedSupplyOutput = try makeTokenOutput(
                address: tokenChangeAddress,
                tokenData: tokenData,
                mapDustError: { Error.tokenGenesisCannotComputeDustThreshold($0) }
            )
            rawOutputs.append(reservedSupplyOutput)
            walletReservedSupplyOutput = reservedSupplyOutput
        }
        
        let organizedOutputs = try await privacyShaper.organizeOutputs(rawOutputs)
        let feeRate = feePolicy.recommendFeeRate(for: genesis.feeContext, override: genesis.feeOverride)
        let bchInputs = try selectBCHInputs(from: spendableOutputs,
                                                            existingInputs: [genesisInput],
                                                            outputs: organizedOutputs,
                                                            feeRate: feeRate,
                                                            shouldAllowDustDonation: genesis.shouldAllowDustDonation,
                                                            changeLockingScript: changeEntry.address.lockingScript.data)
        
        let inputs = [genesisInput] + bchInputs
        let reservedSpendContext = try await reserveSpendContext(
            inputs: inputs,
            outputs: organizedOutputs,
            changeEntry: changeEntry,
            tokenSelectionPolicy: .excludeTokenUTXOs,
            mapReservationError: { Error.coinSelectionFailed($0) },
            mapInsufficientFundsError: Error.transactionBuildFailed(OpalBase.Satoshi.Error.negativeResult),
            beforeReservation: beforeReservation
        )

        let resolvedRawOutputs: [OpalBase.Transaction.Output]
        let resolvedOrganizedOutputs: [OpalBase.Transaction.Output]
        let reservedTokenChangeAddress = try makeTokenAwareAddress(for: reservedSpendContext.changeEntry)
        if let walletReservedSupplyOutput, reservedTokenChangeAddress != tokenChangeAddress {
            let resolvedReservedSupplyOutput = makeRetargetedOutput(walletReservedSupplyOutput,
                                                                    for: reservedTokenChangeAddress)
            resolvedRawOutputs = replacePlannedOutputs(
                in: rawOutputs,
                originals: [walletReservedSupplyOutput],
                replacements: [resolvedReservedSupplyOutput]
            )
            resolvedOrganizedOutputs = replacePlannedOutputs(
                in: organizedOutputs,
                originals: [walletReservedSupplyOutput],
                replacements: [resolvedReservedSupplyOutput]
            )
        } else {
            resolvedRawOutputs = rawOutputs
            resolvedOrganizedOutputs = organizedOutputs
        }
        
        return TokenGenesisPlan(genesis: genesis,
                                category: category,
                                feeRate: feeRate,
                                genesisInput: genesisInput,
                                bchInputs: bchInputs,
                                outputs: resolvedOrganizedOutputs,
                                reservationHandle: reservedSpendContext.reservationHandle,
                                privateKeys: reservedSpendContext.privateKeys,
                                changeOutput: reservedSpendContext.changeOutput,
                                plannedMintedOutputs: resolvedRawOutputs,
                                shouldAllowDustDonation: genesis.shouldAllowDustDonation,
                                shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }
}
