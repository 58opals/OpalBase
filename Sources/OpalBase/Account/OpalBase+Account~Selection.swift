// OpalBase+Account~Selection.swift

import Foundation

extension _OpalBase.Account {
    func selectTokenInputs(from unspentOutputs: [OpalBase.Transaction.Output.Unspent],
                           requirements: TokenRequirements) throws -> [OpalBase.Transaction.Output.Unspent] {
        guard requirements.fungibleAmount > 0 || !requirements.nonFungibleTokens.isEmpty else {
            throw Error.tokenTransferHasNoRecipients
        }
        
        var remainingFungible = requirements.fungibleAmount
        var remainingNonFungible = requirements.nonFungibleTokens
        var selected: [OpalBase.Transaction.Output.Unspent] = .init()
        
        for unspentOutput in unspentOutputs {
            guard let tokenData = unspentOutput.tokenData else { continue }
            guard tokenData.category == requirements.category else { continue }
            var shouldSelect = false
            if remainingFungible > 0, let amount = tokenData.amount, amount > 0 {
                shouldSelect = true
            }
            if let nonFungibleToken = tokenData.nft {
                let group = OpalBase.Address.Book.TokenInventory.NonFungibleTokenGroup(category: tokenData.category,
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
                let group = OpalBase.Address.Book.TokenInventory.NonFungibleTokenGroup(category: tokenData.category,
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
    
    func selectBCHInputs(from unspentOutputs: [OpalBase.Transaction.Output.Unspent],
                                 existingInputs: [OpalBase.Transaction.Output.Unspent],
                                 outputs: [OpalBase.Transaction.Output],
                                 feeRate: UInt64,
                                 shouldAllowDustDonation: Bool,
                                 changeLockingScript: Data) throws -> [OpalBase.Transaction.Output.Unspent] {
        let existingInputSet = Set(existingInputs)
        let bchOnlyOutputs = unspentOutputs
            .filter { $0.tokenData == nil && !existingInputSet.contains($0) }
            .sorted {
                if $0.value == $1.value {
                    return $0.compareOrder(before: $1)
                }
                return $0.value > $1.value
            }
        let targetAmount = try outputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) { try OpalBase.Satoshi($0.value) }.uint64
        let configuration = OpalBase.Address.Book.CoinSelection.Configuration(recipientOutputs: outputs,
                                                                     changeLockingScript: changeLockingScript,
                                                                     strategy: .greedyLargestFirst,
                                                                     shouldAllowDustDonation: shouldAllowDustDonation,
                                                                     tokenSelectionPolicy: .excludeTokenUTXOs)
        let minimumRelayFeeRate = OpalBase.Transaction.minimumRelayFeeRate
        
        func evaluate(total: UInt64, inputCount: Int) throws -> OpalBase.Address.Book.CoinSelection.Evaluation? {
            try OpalBase.Address.Book.CoinSelection.evaluate(configuration: configuration,
                                                    total: total,
                                                    inputCount: inputCount,
                                                    targetAmount: targetAmount,
                                                    recipientOutputs: configuration.recipientOutputs,
                                                    outputsWithChange: configuration.outputsWithChange,
                                                    minimumRelayFeeRate: minimumRelayFeeRate,
                                                    feePerByte: feeRate)
        }
        
        var selected: [OpalBase.Transaction.Output.Unspent] = .init()
        var total: UInt64 = try existingInputs.reduce(0) { partial, output in
            try partial.addOrThrow(output.value,
                                   overflowError: Error.paymentExceedsMaximumAmount)
        }
        if try evaluate(total: total, inputCount: existingInputs.count) != nil {
            return selected
        }
        
        for output in bchOnlyOutputs {
            selected.append(output)
            total = try total.addOrThrow(output.value,
                                         overflowError: Error.paymentExceedsMaximumAmount)
            if try evaluate(total: total, inputCount: existingInputs.count + selected.count) != nil {
                return selected
            }
        }
        
        let feeWithChange = try OpalBase.Transaction.estimateFee(inputCount: existingInputs.count + selected.count,
                                                        outputs: configuration.outputsWithChange,
                                                        feePerByte: feeRate)
        let requiredWithChange = try targetAmount.addOrThrow(feeWithChange,
                                                             overflowError: Error.paymentExceedsMaximumAmount)
        let requiredAdditional = requiredWithChange > total ? (requiredWithChange - total) : 0
        throw Error.tokenTransferInsufficientFunds(required: requiredAdditional)
    }
}
