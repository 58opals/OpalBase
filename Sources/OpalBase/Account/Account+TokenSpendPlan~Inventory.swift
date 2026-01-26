// Account+TokenSpendPlan~Inventory.swift

import Foundation

extension Account {
    struct TokenRequirements {
        let category: CashTokens.CategoryID
        let fungibleAmount: UInt64
        let nonFungibleTokens: [Address.Book.TokenInventory.NonFungibleTokenGroup: Int]
    }
    
    struct TokenInventory {
        let category: CashTokens.CategoryID
        let fungibleAmount: UInt64
        let nonFungibleTokens: [Address.Book.TokenInventory.NonFungibleTokenGroup: Int]
    }
}

extension Account {
    func makeTokenRequirements(for transfer: TokenTransfer,
                               category: CashTokens.CategoryID) throws -> TokenRequirements {
        var fungibleAmount: UInt64 = 0
        var nonFungibleTokens: [Address.Book.TokenInventory.NonFungibleTokenGroup: Int] = .init()
        for recipient in transfer.recipients {
            fungibleAmount = try addTokenAmounts(fungibleAmount, recipient.tokenData.amount ?? 0)
            if let nonFungibleToken = recipient.tokenData.nft {
                let group = Address.Book.TokenInventory.NonFungibleTokenGroup(category: category,
                                                                              commitment: nonFungibleToken.commitment,
                                                                              capability: nonFungibleToken.capability)
                nonFungibleTokens[group, default: 0] += 1
            }
        }
        for burn in transfer.burns {
            fungibleAmount = try addTokenAmounts(fungibleAmount, burn.tokenData.amount ?? 0)
            if let nonFungibleToken = burn.tokenData.nft {
                let group = Address.Book.TokenInventory.NonFungibleTokenGroup(category: category,
                                                                              commitment: nonFungibleToken.commitment,
                                                                              capability: nonFungibleToken.capability)
                nonFungibleTokens[group, default: 0] += 1
            }
        }
        return TokenRequirements(category: category,
                                 fungibleAmount: fungibleAmount,
                                 nonFungibleTokens: nonFungibleTokens)
    }
    
    func makeTokenInventory(from unspentOutputs: [Transaction.Output.Unspent],
                            category: CashTokens.CategoryID) throws -> TokenInventory {
        var fungibleAmount: UInt64 = 0
        var nonFungibleTokens: [Address.Book.TokenInventory.NonFungibleTokenGroup: Int] = .init()
        for unspentOutput in unspentOutputs {
            guard let tokenData = unspentOutput.tokenData else { continue }
            if let amount = tokenData.amount {
                fungibleAmount = try addTokenAmounts(fungibleAmount, amount)
            }
            if let nonFungibleToken = tokenData.nft {
                let group = Address.Book.TokenInventory.NonFungibleTokenGroup(category: tokenData.category,
                                                                              commitment: nonFungibleToken.commitment,
                                                                              capability: nonFungibleToken.capability)
                nonFungibleTokens[group, default: 0] += 1
            }
        }
        return TokenInventory(category: category,
                              fungibleAmount: fungibleAmount,
                              nonFungibleTokens: nonFungibleTokens)
    }
    
    func subtractTokenInventory(input: TokenInventory,
                                requirements: TokenRequirements) throws -> TokenInventory {
        guard input.fungibleAmount >= requirements.fungibleAmount else {
            throw Error.tokenTransferInsufficientTokens
        }
        let remainingFungible = input.fungibleAmount - requirements.fungibleAmount
        var remainingNonFungible: [Address.Book.TokenInventory.NonFungibleTokenGroup: Int] = .init()
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
        return TokenInventory(category: input.category,
                              fungibleAmount: remainingFungible,
                              nonFungibleTokens: remainingNonFungible)
    }
    
    func makeTokenChangeOutputs(from inventory: TokenInventory,
                                changeAddress: Address) throws -> [Transaction.Output] {
        var outputs: [Transaction.Output] = .init()
        var remainingFungible = inventory.fungibleAmount
        for (group, count) in inventory.nonFungibleTokens where count > 0 {
            for _ in 0..<count {
                let nonFungibleToken = try CashTokens.NFT(capability: group.capability,
                                                          commitment: group.commitment)
                let amount: UInt64? = (outputs.isEmpty && remainingFungible > 0) ? remainingFungible : nil
                if outputs.isEmpty && remainingFungible > 0 {
                    remainingFungible = 0
                }
                let tokenData = CashTokens.TokenData(category: group.category,
                                                     amount: amount,
                                                     nft: nonFungibleToken)
                outputs.append(Transaction.Output(value: Transaction.dustLimit,
                                                  address: changeAddress,
                                                  tokenData: tokenData))
            }
        }
        if remainingFungible > 0 {
            let tokenData = CashTokens.TokenData(category: inventory.category,
                                                 amount: remainingFungible,
                                                 nft: nil)
            outputs.append(Transaction.Output(value: Transaction.dustLimit,
                                              address: changeAddress,
                                              tokenData: tokenData))
        }
        return outputs
    }
    
    func addTokenAmounts(_ left: UInt64, _ right: UInt64) throws -> UInt64 {
        let (sum, overflow) = left.addingReportingOverflow(right)
        if overflow { throw Error.paymentExceedsMaximumAmount }
        return sum
    }
}
