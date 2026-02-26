// WalletActor~TokenInventoryModel.swift

import Foundation

extension WalletActor {
    public func loadUnspentOutputBalances() async throws -> AddressModel.BookActor.UnspentOutputBalancesModel {
        var bchTotal = SatoshiModel()
        var bchSpendable = SatoshiModel()
        var fungibleAmountsByCategory: [CashTokensModel.CategoryIDModel: UInt64] = .init()
        var nonFungibleTokensByGroup: [AddressModel.BookActor.TokenInventoryModel.NonFungibleTokenGroup: Int] = .init()
        
        for account in accounts.values {
            let balances = try await account.loadUnspentOutputBalances()
            bchTotal = try bchTotal + balances.bchTotal
            bchSpendable = try bchSpendable + balances.bchSpendable
            try mergeFungibleAmounts(from: balances.tokenInventory.fungibleAmountsByCategory,
                                     into: &fungibleAmountsByCategory)
            mergeNonFungibleTokens(from: balances.tokenInventory.nonFungibleTokensByGroup,
                                   into: &nonFungibleTokensByGroup)
        }
        
        let tokenInventory = AddressModel.BookActor.TokenInventoryModel(fungibleAmountsByCategory: fungibleAmountsByCategory,
                                                         nonFungibleTokensByGroup: nonFungibleTokensByGroup)
        return AddressModel.BookActor.UnspentOutputBalancesModel(bchTotal: bchTotal,
                                                  bchSpendable: bchSpendable,
                                                  tokenInventory: tokenInventory)
    }
    
    public func loadTokenInventory() async throws -> AddressModel.BookActor.TokenInventoryModel {
        let balances = try await loadUnspentOutputBalances()
        return balances.tokenInventory
    }
}

private extension WalletActor {
    func mergeFungibleAmounts(from additions: [CashTokensModel.CategoryIDModel: UInt64],
                              into totals: inout [CashTokensModel.CategoryIDModel: UInt64]) throws {
        for (category, amount) in additions {
            let current = totals[category] ?? 0
            totals[category] = try current.addOrThrow(
                amount,
                overflowError: AccountActor.Error.paymentExceedsMaximumAmount
            )
        }
    }
    
    func mergeNonFungibleTokens(from additions: [AddressModel.BookActor.TokenInventoryModel.NonFungibleTokenGroup: Int],
                                into totals: inout [AddressModel.BookActor.TokenInventoryModel.NonFungibleTokenGroup: Int]) {
        for (group, count) in additions {
            totals[group, default: 0] += count
        }
    }
}
