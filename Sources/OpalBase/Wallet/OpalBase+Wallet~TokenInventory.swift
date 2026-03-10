// OpalBase+Wallet~TokenInventory.swift

import Foundation

extension _OpalBase.Wallet {
    public func loadUnspentOutputBalances() async throws -> OpalBase.Address.Book.UnspentOutputBalances {
        var bchTotal = OpalBase.Satoshi()
        var bchSpendable = OpalBase.Satoshi()
        var fungibleAmountsByCategory: [OpalBase.CashTokens.CategoryID: UInt64] = .init()
        var nonFungibleTokensByGroup: [OpalBase.Address.Book.TokenInventory.NonFungibleTokenGroup: Int] = .init()
        
        for account in accounts.values {
            let balances = try await account.loadUnspentOutputBalances()
            bchTotal = try bchTotal + balances.bchTotal
            bchSpendable = try bchSpendable + balances.bchSpendable
            try mergeFungibleAmounts(from: balances.tokenInventory.fungibleAmountsByCategory,
                                     into: &fungibleAmountsByCategory)
            mergeNonFungibleTokens(from: balances.tokenInventory.nonFungibleTokensByGroup,
                                   into: &nonFungibleTokensByGroup)
        }
        
        let tokenInventory = OpalBase.Address.Book.TokenInventory(fungibleAmountsByCategory: fungibleAmountsByCategory,
                                                         nonFungibleTokensByGroup: nonFungibleTokensByGroup)
        return OpalBase.Address.Book.UnspentOutputBalances(bchTotal: bchTotal,
                                                  bchSpendable: bchSpendable,
                                                  tokenInventory: tokenInventory)
    }
    
    public func loadTokenInventory() async throws -> OpalBase.Address.Book.TokenInventory {
        let balances = try await loadUnspentOutputBalances()
        return balances.tokenInventory
    }
}

private extension _OpalBase.Wallet {
    func mergeFungibleAmounts(from additions: [OpalBase.CashTokens.CategoryID: UInt64],
                              into totals: inout [OpalBase.CashTokens.CategoryID: UInt64]) throws {
        for (category, amount) in additions {
            let current = totals[category] ?? 0
            totals[category] = try current.addOrThrow(
                amount,
                overflowError: OpalBase.Account.Error.paymentExceedsMaximumAmount
            )
        }
    }
    
    func mergeNonFungibleTokens(from additions: [OpalBase.Address.Book.TokenInventory.NonFungibleTokenGroup: Int],
                                into totals: inout [OpalBase.Address.Book.TokenInventory.NonFungibleTokenGroup: Int]) {
        for (group, count) in additions {
            totals[group, default: 0] += count
        }
    }
}

