// AccountActor+TokenSpendPlanModel~InventoryModel.swift

import Foundation

extension AccountActor {
    typealias TokenRequirementsByCategory = [CashTokensModel.CategoryIDModel: TokenRequirementsModel]
    
    struct TokenRequirementsModel {
        let category: CashTokensModel.CategoryIDModel
        let fungibleAmount: UInt64
        let nonFungibleTokens: [AddressModel.BookActor.TokenInventoryModel.NonFungibleTokenGroup: Int]
    }
    
    struct TokenInventoryModel {
        let category: CashTokensModel.CategoryIDModel
        let fungibleAmount: UInt64
        let nonFungibleTokens: [AddressModel.BookActor.TokenInventoryModel.NonFungibleTokenGroup: Int]
    }
}

extension AccountActor {
    func makeTokenRequirementsByCategory(for transfer: TokenTransferModel) throws -> TokenRequirementsByCategory {
        var requirementsByCategory: TokenRequirementsByCategory = .init()
        
        func updateRequirements(with tokenData: CashTokensModel.TokenData) throws {
            let category = tokenData.category
            var requirements = requirementsByCategory[category] ?? TokenRequirementsModel(category: category,
                                                                                     fungibleAmount: 0,
                                                                                     nonFungibleTokens: .init())
            if let amount = tokenData.amount {
                requirements = TokenRequirementsModel(category: category,
                                                 fungibleAmount: try requirements.fungibleAmount.addOrThrow(
                                                    amount,
                                                    overflowError: Error.paymentExceedsMaximumAmount
                                                 ),
                                                 nonFungibleTokens: requirements.nonFungibleTokens)
            }
            if let nonFungibleToken = tokenData.nft {
                var nonFungibleTokens = requirements.nonFungibleTokens
                let group = AddressModel.BookActor.TokenInventoryModel.NonFungibleTokenGroup(category: category,
                                                                              commitment: nonFungibleToken.commitment,
                                                                              capability: nonFungibleToken.capability)
                nonFungibleTokens[group, default: 0] += 1
                requirements = TokenRequirementsModel(category: category,
                                                 fungibleAmount: requirements.fungibleAmount,
                                                 nonFungibleTokens: nonFungibleTokens)
            }
            requirementsByCategory[category] = requirements
        }
        
        for recipient in transfer.recipients {
            try updateRequirements(with: recipient.tokenData)
        }
        for burn in transfer.burns {
            try updateRequirements(with: burn.tokenData)
        }
        
        return requirementsByCategory
    }
    
    func makeTokenInventory(from unspentOutputs: [TransactionModel.OutputModel.UnspentModel],
                            category: CashTokensModel.CategoryIDModel) throws -> TokenInventoryModel {
        var fungibleAmount: UInt64 = 0
        var nonFungibleTokens: [AddressModel.BookActor.TokenInventoryModel.NonFungibleTokenGroup: Int] = .init()
        for unspentOutput in unspentOutputs {
            guard let tokenData = unspentOutput.tokenData else { continue }
            if let amount = tokenData.amount {
                fungibleAmount = try fungibleAmount.addOrThrow(amount,
                                                               overflowError: Error.paymentExceedsMaximumAmount)
            }
            if let nonFungibleToken = tokenData.nft {
                let group = AddressModel.BookActor.TokenInventoryModel.NonFungibleTokenGroup(category: tokenData.category,
                                                                              commitment: nonFungibleToken.commitment,
                                                                              capability: nonFungibleToken.capability)
                nonFungibleTokens[group, default: 0] += 1
            }
        }
        return TokenInventoryModel(category: category,
                              fungibleAmount: fungibleAmount,
                              nonFungibleTokens: nonFungibleTokens)
    }
    
    func subtractTokenInventory(input: TokenInventoryModel,
                                requirements: TokenRequirementsModel) throws -> TokenInventoryModel {
        guard input.fungibleAmount >= requirements.fungibleAmount else {
            throw Error.tokenTransferInsufficientTokens
        }
        let remainingFungible = input.fungibleAmount - requirements.fungibleAmount
        var remainingNonFungible: [AddressModel.BookActor.TokenInventoryModel.NonFungibleTokenGroup: Int] = .init()
        for (group, count) in input.nonFungibleTokens {
            let requiredCount = requirements.nonFungibleTokens[group] ?? 0
            guard count >= requiredCount else {
                throw Error.tokenTransferInsufficientTokens
            }
            let remainder = count - requiredCount
            if remainder > 0 {
                remainingNonFungible[group] = remainder
            }
        }
        for (group, count) in requirements.nonFungibleTokens where count > 0 {
            guard input.nonFungibleTokens[group] != nil else {
                throw Error.tokenTransferInsufficientTokens
            }
        }
        return TokenInventoryModel(category: input.category,
                              fungibleAmount: remainingFungible,
                              nonFungibleTokens: remainingNonFungible)
    }
    
    func makeTokenChangeOutputs(from inventory: TokenInventoryModel,
                                changeAddress: AddressModel) throws -> [TransactionModel.OutputModel] {
        var outputs: [TransactionModel.OutputModel] = .init()
        var remainingFungible = inventory.fungibleAmount
        let minimumRelayFeeRate = TransactionModel.minimumRelayFeeRate
        for (group, count) in inventory.nonFungibleTokens where count > 0 {
            for _ in 0..<count {
                let nonFungibleToken = try CashTokensModel.NFTModel(capability: group.capability,
                                                          commitment: group.commitment)
                let amount: UInt64? = (outputs.isEmpty && remainingFungible > 0) ? remainingFungible : nil
                if outputs.isEmpty && remainingFungible > 0 {
                    remainingFungible = 0
                }
                let tokenData = CashTokensModel.TokenData(category: group.category,
                                                     amount: amount,
                                                     nft: nonFungibleToken)
                let outputTemplate = TransactionModel.OutputModel(value: 0,
                                                        address: changeAddress,
                                                        tokenData: tokenData)
                let dustThreshold = try outputTemplate.calculateDustThreshold(feeRate: minimumRelayFeeRate)
                outputs.append(TransactionModel.OutputModel(value: dustThreshold,
                                                  address: changeAddress,
                                                  tokenData: tokenData))
            }
        }
        if remainingFungible > 0 {
            let tokenData = CashTokensModel.TokenData(category: inventory.category,
                                                 amount: remainingFungible,
                                                 nft: nil)
            let outputTemplate = TransactionModel.OutputModel(value: 0,
                                                    address: changeAddress,
                                                    tokenData: tokenData)
            let dustThreshold = try outputTemplate.calculateDustThreshold(feeRate: minimumRelayFeeRate)
            outputs.append(TransactionModel.OutputModel(value: dustThreshold,
                                              address: changeAddress,
                                              tokenData: tokenData))
        }
        return outputs
    }
}
