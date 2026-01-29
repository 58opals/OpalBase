// Account~TokenGenesisPlanning.swift

import Foundation

extension Account {
    public func prepareTokenGenesis(
        _ genesis: TokenGenesis,
        preferredGenesisInput: Transaction.Output.Unspent? = nil,
        feePolicy: Wallet.FeePolicy = .init()
    ) async throws -> TokenGenesisPlan {
        guard !genesis.recipients.isEmpty || genesis.reservedSupplyToSelf != nil else {
            throw Error.tokenGenesisHasNoRecipients
        }
        
        let unsafeRecipients = genesis.recipients.filter { !$0.address.supportsTokens }
        if !unsafeRecipients.isEmpty {
            throw Error.tokenGenesisRequiresTokenAwareAddress(unsafeRecipients.map(\.address))
        }
        
        let spendableOutputs = await addressBook.sortSpendableUTXOs(by: { $0.value > $1.value })
        let genesisInput: Transaction.Output.Unspent
        if let preferredGenesisInput {
            guard preferredGenesisInput.tokenData == nil,
                  preferredGenesisInput.previousTransactionOutputIndex == 0 else {
                throw Error.tokenGenesisInvalidGenesisInput
            }
            let spendableSet = Set(spendableOutputs)
            if !spendableSet.contains(preferredGenesisInput) {
                let allOutputs = await addressBook.sortUTXOs(by: { $0.value > $1.value })
                guard allOutputs.contains(preferredGenesisInput) else {
                    throw Error.tokenGenesisInvalidGenesisInput
                }
            }
            genesisInput = preferredGenesisInput
        } else {
            guard let selectedGenesisInput = selectGenesisInput(from: spendableOutputs) else {
                // Consider calling prepareTokenGenesisOutpoint to identify a valid genesis input.
                throw Error.tokenGenesisNoEligibleGenesisInput
            }
            genesisInput = selectedGenesisInput
        }
        
        let category: CashTokens.CategoryID
        do {
            category = try CashTokens.CategoryID(transactionOrderData: genesisInput.previousTransactionHash.naturalOrder)
        } catch {
            throw Error.tokenGenesisInvalidGenesisInput
        }
        
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        let minimumRelayFeeRate = Transaction.minimumRelayFeeRate
        var rawOutputs: [Transaction.Output] = .init()
        for recipient in genesis.recipients {
            let tokenData = CashTokens.TokenData(category: category,
                                                 amount: recipient.fungibleAmount,
                                                 nft: recipient.nft)
            let outputTemplate = Transaction.Output(value: 0,
                                                    address: recipient.address,
                                                    tokenData: tokenData)
            let dustThreshold: UInt64
            do {
                dustThreshold = try outputTemplate.dustThreshold(feeRate: minimumRelayFeeRate)
            } catch {
                throw Error.tokenGenesisCannotComputeDustThreshold(error)
            }
            let outputValue: UInt64
            if let bchAmount = recipient.bchAmount {
                guard bchAmount.uint64 >= dustThreshold else {
                    throw Error.tokenGenesisInvalidGenesisInput
                }
                outputValue = bchAmount.uint64
            } else {
                outputValue = dustThreshold
            }
            rawOutputs.append(Transaction.Output(value: outputValue,
                                                 address: recipient.address,
                                                 tokenData: tokenData))
        }
        
        if let reservedSupply = genesis.reservedSupplyToSelf {
            let tokenChangeAddress = try Address(script: changeEntry.address.lockingScript,
                                                 format: .tokenAware)
            let mintingToken: CashTokens.NFT?
            if reservedSupply.includeMintingNFT {
                do {
                    mintingToken = try CashTokens.NFT(capability: .minting,
                                                      commitment: reservedSupply.commitment)
                } catch {
                    throw Error.tokenGenesisInvalidGenesisInput
                }
            } else {
                mintingToken = nil
            }
            let tokenData = CashTokens.TokenData(category: category,
                                                 amount: reservedSupply.fungibleAmount,
                                                 nft: mintingToken)
            let outputTemplate = Transaction.Output(value: 0,
                                                    address: tokenChangeAddress,
                                                    tokenData: tokenData)
            let dustThreshold: UInt64
            do {
                dustThreshold = try outputTemplate.dustThreshold(feeRate: minimumRelayFeeRate)
            } catch {
                throw Error.tokenGenesisCannotComputeDustThreshold(error)
            }
            rawOutputs.append(Transaction.Output(value: dustThreshold,
                                                 address: tokenChangeAddress,
                                                 tokenData: tokenData))
        }
        
        let organizedOutputs = await privacyShaper.organizeOutputs(rawOutputs)
        let feeRate = feePolicy.recommendFeeRate(for: genesis.feeContext, override: genesis.feeOverride)
        let bitcoinCashInputs = try selectBitcoinCashInputs(from: spendableOutputs,
                                                            existingInputs: [genesisInput],
                                                            outputs: organizedOutputs,
                                                            feeRate: feeRate,
                                                            shouldAllowDustDonation: genesis.shouldAllowDustDonation,
                                                            changeLockingScript: changeEntry.address.lockingScript.data)
        
        let inputs = [genesisInput] + bitcoinCashInputs
        let totalSelectedAmount = try inputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try Satoshi($0.value)
        }
        let targetAmount = try organizedOutputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) {
            try Satoshi($0.value)
        }
        let initialChangeAmount = try totalSelectedAmount - targetAmount
        let (reservation, reservedChangeEntry, privateKeys) = try await reserveSpendAndDeriveKeys(
            utxos: inputs,
            changeEntry: changeEntry,
            tokenSelectionPolicy: .excludeTokenUTXOs,
            mapReservationError: { Error.coinSelectionFailed($0) }
        )
        let reservationHandle = Account.SpendReservation(addressBook: addressBook, reservation: reservation)
        let changeOutput = Transaction.Output(value: initialChangeAmount.uint64, address: reservedChangeEntry.address)
        
        return TokenGenesisPlan(genesis: genesis,
                                category: category,
                                feeRate: feeRate,
                                genesisInput: genesisInput,
                                bitcoinCashInputs: bitcoinCashInputs,
                                outputs: organizedOutputs,
                                reservationHandle: reservationHandle,
                                privateKeys: privateKeys,
                                changeOutput: changeOutput,
                                plannedMintedOutputs: rawOutputs,
                                shouldAllowDustDonation: genesis.shouldAllowDustDonation,
                                shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
    }
}
