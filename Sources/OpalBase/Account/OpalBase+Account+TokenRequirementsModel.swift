// OpalBase+Account+TokenRequirementsModel.swift

import Foundation

extension _OpalBase.Account {
    typealias TokenRequirementsByCategory = [OpalBase.CashTokens.CategoryIDModel: TokenRequirementsModel]
    
    struct TokenRequirementsModel {
        let category: OpalBase.CashTokens.CategoryIDModel
        let fungibleAmount: UInt64
        let nonFungibleTokens: [OpalBase.Address.Book.TokenInventoryModel.NonFungibleTokenGroup: Int]
    }
    
    struct TokenInventoryModel {
        let category: OpalBase.CashTokens.CategoryIDModel
        let fungibleAmount: UInt64
        let nonFungibleTokens: [OpalBase.Address.Book.TokenInventoryModel.NonFungibleTokenGroup: Int]
    }
}

extension _OpalBase.Account {
    func makeTokenRequirementsByCategory(for transfer: TokenTransfer) throws -> TokenRequirementsByCategory {
        var requirementsByCategory: TokenRequirementsByCategory = .init()
        
        func updateRequirements(with tokenData: OpalBase.CashTokens.TokenData) throws {
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
                let group = OpalBase.Address.Book.TokenInventoryModel.NonFungibleTokenGroup(category: category,
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
    
    func makeTokenInventory(from unspentOutputs: [OpalBase.Transaction.OutputModel.UnspentModel],
                            category: OpalBase.CashTokens.CategoryIDModel) throws -> TokenInventoryModel {
        var fungibleAmount: UInt64 = 0
        var nonFungibleTokens: [OpalBase.Address.Book.TokenInventoryModel.NonFungibleTokenGroup: Int] = .init()
        for unspentOutput in unspentOutputs {
            guard let tokenData = unspentOutput.tokenData else { continue }
            if let amount = tokenData.amount {
                fungibleAmount = try fungibleAmount.addOrThrow(amount,
                                                               overflowError: Error.paymentExceedsMaximumAmount)
            }
            if let nonFungibleToken = tokenData.nft {
                let group = OpalBase.Address.Book.TokenInventoryModel.NonFungibleTokenGroup(category: tokenData.category,
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
        var remainingNonFungible: [OpalBase.Address.Book.TokenInventoryModel.NonFungibleTokenGroup: Int] = .init()
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
                                changeAddress: OpalBase.Address) throws -> [OpalBase.Transaction.OutputModel] {
        var outputs: [OpalBase.Transaction.OutputModel] = .init()
        var remainingFungible = inventory.fungibleAmount
        let minimumRelayFeeRate = OpalBase.Transaction.minimumRelayFeeRate
        for (group, count) in inventory.nonFungibleTokens where count > 0 {
            for _ in 0..<count {
                let nonFungibleToken = try OpalBase.CashTokens.NFTModel(capability: group.capability,
                                                          commitment: group.commitment)
                let amount: UInt64? = (outputs.isEmpty && remainingFungible > 0) ? remainingFungible : nil
                if outputs.isEmpty && remainingFungible > 0 {
                    remainingFungible = 0
                }
                let tokenData = OpalBase.CashTokens.TokenData(category: group.category,
                                                     amount: amount,
                                                     nft: nonFungibleToken)
                let outputTemplate = OpalBase.Transaction.OutputModel(value: 0,
                                                        address: changeAddress,
                                                        tokenData: tokenData)
                let dustThreshold = try outputTemplate.calculateDustThreshold(feeRate: minimumRelayFeeRate)
                outputs.append(OpalBase.Transaction.OutputModel(value: dustThreshold,
                                                  address: changeAddress,
                                                  tokenData: tokenData))
            }
        }
        if remainingFungible > 0 {
            let tokenData = OpalBase.CashTokens.TokenData(category: inventory.category,
                                                 amount: remainingFungible,
                                                 nft: nil)
            let outputTemplate = OpalBase.Transaction.OutputModel(value: 0,
                                                    address: changeAddress,
                                                    tokenData: tokenData)
            let dustThreshold = try outputTemplate.calculateDustThreshold(feeRate: minimumRelayFeeRate)
            outputs.append(OpalBase.Transaction.OutputModel(value: dustThreshold,
                                              address: changeAddress,
                                              tokenData: tokenData))
        }
        return outputs
    }
}

