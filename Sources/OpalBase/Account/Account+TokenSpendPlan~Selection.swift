// Account+TokenSpendPlan~Selection.swift

import Foundation

extension Account {
    func resolveTokenCategory(from transfer: TokenTransfer) throws -> CashTokens.CategoryID {
        let categories = transfer.recipients.map(\.tokenData.category) + transfer.burns.map(\.tokenData.category)
        guard let firstCategory = categories.first else { throw Error.tokenTransferHasNoRecipients }
        if categories.contains(where: { $0 != firstCategory }) {
            throw Error.tokenTransferRequiresSingleCategory
        }
        return firstCategory
    }
    
    func selectTokenInputs(from unspentOutputs: [Transaction.Output.Unspent],
                           requirements: TokenRequirements) throws -> [Transaction.Output.Unspent] {
        guard requirements.fungibleAmount > 0 || !requirements.nonFungibleTokens.isEmpty else {
            throw Error.tokenTransferHasNoRecipients
        }
        
        var remainingFungible = requirements.fungibleAmount
        var remainingNonFungible = requirements.nonFungibleTokens
        var selected: [Transaction.Output.Unspent] = .init()
        
        for unspentOutput in unspentOutputs {
            guard let tokenData = unspentOutput.tokenData else { continue }
            var shouldSelect = false
            if remainingFungible > 0, let amount = tokenData.amount, amount > 0 {
                shouldSelect = true
            }
            if let nonFungibleToken = tokenData.nft {
                let group = Address.Book.TokenInventory.NonFungibleTokenGroup(category: tokenData.category,
                                                                              commitment: nonFungibleToken.commitment,
                                                                              capability: nonFungibleToken.capability)
                if let remainingCount = remainingNonFungible[group], remainingCount > 0 {
                    shouldSelect = true
                }
            }
            guard shouldSelect else { continue }
            
            selected.append(unspentOutput)
            if let amount = tokenData.amount, amount > 0 {
                if remainingFungible <= amount {
                    remainingFungible = 0
                } else {
                    remainingFungible -= amount
                }
            }
            if let nonFungibleToken = tokenData.nft {
                let group = Address.Book.TokenInventory.NonFungibleTokenGroup(category: tokenData.category,
                                                                              commitment: nonFungibleToken.commitment,
                                                                              capability: nonFungibleToken.capability)
                if let remainingCount = remainingNonFungible[group], remainingCount > 0 {
                    remainingNonFungible[group] = remainingCount - 1
                }
            }
            let hasRemainingFungible = remainingFungible > 0
            let hasRemainingNonFungible = remainingNonFungible.values.contains { $0 > 0 }
            if !hasRemainingFungible && !hasRemainingNonFungible {
                return selected
            }
        }
        
        throw Error.tokenTransferInsufficientTokens
    }
    
    func selectBitcoinCashInputs(from unspentOutputs: [Transaction.Output.Unspent],
                                 existingInputs: [Transaction.Output.Unspent],
                                 outputs: [Transaction.Output],
                                 feeRate: UInt64,
                                 shouldAllowDustDonation: Bool,
                                 changeLockingScript: Data) throws -> [Transaction.Output.Unspent] {
        let bitcoinCashOnlyOutputs = unspentOutputs.filter { $0.tokenData == nil }
        let targetAmount = try outputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) { try Satoshi($0.value) }.uint64
        let configuration = Address.Book.CoinSelection.Configuration(recipientOutputs: outputs,
                                                                     changeLockingScript: changeLockingScript,
                                                                     strategy: .greedyLargestFirst,
                                                                     shouldAllowDustDonation: shouldAllowDustDonation,
                                                                     tokenSelectionPolicy: .excludeTokenUTXOs)
        let minimumRelayFeeRate = Transaction.minimumRelayFeeRate
        
        func evaluate(total: UInt64, inputCount: Int) throws -> Address.Book.CoinSelection.Evaluation? {
            try Address.Book.CoinSelection.evaluate(configuration: configuration,
                                                    total: total,
                                                    inputCount: inputCount,
                                                    targetAmount: targetAmount,
                                                    recipientOutputs: configuration.recipientOutputs,
                                                    outputsWithChange: configuration.outputsWithChange,
                                                    minimumRelayFeeRate: minimumRelayFeeRate,
                                                    feePerByte: feeRate)
        }
        
        var selected: [Transaction.Output.Unspent] = .init()
        var total: UInt64 = try existingInputs.reduce(0) { partial, output in
            try partial.addingOrThrow(output.value,
                                      overflowError: Error.paymentExceedsMaximumAmount)
        }
        if try evaluate(total: total, inputCount: existingInputs.count) != nil {
            return selected
        }
        
        for output in bitcoinCashOnlyOutputs {
            selected.append(output)
            total = try total.addingOrThrow(output.value,
                                            overflowError: Error.paymentExceedsMaximumAmount)
            if try evaluate(total: total, inputCount: existingInputs.count + selected.count) != nil {
                return selected
            }
        }
        
        let feeWithChange = try Transaction.estimateFee(inputCount: existingInputs.count + selected.count,
                                                        outputs: configuration.outputsWithChange,
                                                        feePerByte: feeRate)
        let requiredWithChange = try targetAmount.addingOrThrow(feeWithChange,
                                                                overflowError: Error.paymentExceedsMaximumAmount)
        let requiredAdditional = requiredWithChange > total ? (requiredWithChange - total) : 0
        throw Error.tokenTransferInsufficientFunds(required: requiredAdditional)
    }
}
