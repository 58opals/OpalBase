// Wallet~TokenInventory.swift

import Foundation

extension Wallet {
    public func loadUnspentOutputBalances() async throws -> Address.Book.UnspentOutputBalances {
        var bchTotal = Satoshi()
        var bchSpendable = Satoshi()
        var fungibleAmountsByCategory: [CashTokens.CategoryID: UInt64] = .init()
        var nonFungibleTokensByGroup: [Address.Book.TokenInventory.NonFungibleTokenGroup: Int] = .init()
        
        for account in accounts.values {
            let balances = try await account.loadUnspentOutputBalances()
            bchTotal = try bchTotal + balances.bchTotal
            bchSpendable = try bchSpendable + balances.bchSpendable
            try mergeFungibleAmounts(from: balances.tokenInventory.fungibleAmountsByCategory,
                                     into: &fungibleAmountsByCategory)
            mergeNonFungibleTokens(from: balances.tokenInventory.nonFungibleTokensByGroup,
                                   into: &nonFungibleTokensByGroup)
        }
        
        let tokenInventory = Address.Book.TokenInventory(fungibleAmountsByCategory: fungibleAmountsByCategory,
                                                         nonFungibleTokensByGroup: nonFungibleTokensByGroup)
        return Address.Book.UnspentOutputBalances(bchTotal: bchTotal,
                                                  bchSpendable: bchSpendable,
                                                  tokenInventory: tokenInventory)
    }
    
    public func loadTokenInventory() async throws -> Address.Book.TokenInventory {
        let balances = try await loadUnspentOutputBalances()
        return balances.tokenInventory
    }
}

private extension Wallet {
    func mergeFungibleAmounts(from additions: [CashTokens.CategoryID: UInt64],
                              into totals: inout [CashTokens.CategoryID: UInt64]) throws {
        for (category, amount) in additions {
            let current = totals[category] ?? 0
            totals[category] = try addTokenAmounts(current, amount)
        }
    }
    
    func mergeNonFungibleTokens(from additions: [Address.Book.TokenInventory.NonFungibleTokenGroup: Int],
                                into totals: inout [Address.Book.TokenInventory.NonFungibleTokenGroup: Int]) {
        for (group, count) in additions {
            totals[group, default: 0] += count
        }
    }
    
    func addTokenAmounts(_ left: UInt64, _ right: UInt64) throws -> UInt64 {
        let (sum, overflow) = left.addingReportingOverflow(right)
        if overflow {
            throw Account.Error.paymentExceedsMaximumAmount
        }
        return sum
    }
}
