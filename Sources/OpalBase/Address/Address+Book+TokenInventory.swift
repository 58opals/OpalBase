// Address+Book+TokenInventory.swift

import Foundation

extension Address.Book {
    public struct TokenInventory: Sendable, Equatable {
        public struct NonFungibleTokenGroup: Hashable, Sendable {
            public let category: CashTokens.CategoryID
            public let commitment: Data
            public let capability: CashTokens.NFT.Capability
            
            public init(category: CashTokens.CategoryID,
                        commitment: Data,
                        capability: CashTokens.NFT.Capability) {
                self.category = category
                self.commitment = commitment
                self.capability = capability
            }
        }
        
        public let fungibleAmountsByCategory: [CashTokens.CategoryID: UInt64]
        public let nonFungibleTokensByGroup: [NonFungibleTokenGroup: Int]
        
        public init(fungibleAmountsByCategory: [CashTokens.CategoryID: UInt64],
                    nonFungibleTokensByGroup: [NonFungibleTokenGroup: Int]) {
            self.fungibleAmountsByCategory = fungibleAmountsByCategory
            self.nonFungibleTokensByGroup = nonFungibleTokensByGroup
        }
    }
    
    public struct UnspentOutputPartition: Sendable, Equatable {
        public let bchOnlyUTXOs: Set<Transaction.Output.Unspent>
        public let tokenUTXOs: Set<Transaction.Output.Unspent>
        
        public init(bchOnlyUTXOs: Set<Transaction.Output.Unspent>,
                    tokenUTXOs: Set<Transaction.Output.Unspent>) {
            self.bchOnlyUTXOs = bchOnlyUTXOs
            self.tokenUTXOs = tokenUTXOs
        }
    }
    
    public struct UnspentOutputBalances: Sendable, Equatable {
        public let bchTotal: Satoshi
        public let bchSpendable: Satoshi
        public let tokenInventory: TokenInventory
        
        public init(bchTotal: Satoshi,
                    bchSpendable: Satoshi,
                    tokenInventory: TokenInventory) {
            self.bchTotal = bchTotal
            self.bchSpendable = bchSpendable
            self.tokenInventory = tokenInventory
        }
    }
}

extension Address.Book {
    public func partitionUnspentOutputs() -> UnspentOutputPartition {
        let utxos = listUTXOs()
        var bchOnlyUTXOs: Set<Transaction.Output.Unspent> = .init()
        var tokenUTXOs: Set<Transaction.Output.Unspent> = .init()
        for utxo in utxos {
            if utxo.tokenData == nil {
                bchOnlyUTXOs.insert(utxo)
            } else {
                tokenUTXOs.insert(utxo)
            }
        }
        return UnspentOutputPartition(bchOnlyUTXOs: bchOnlyUTXOs,
                                      tokenUTXOs: tokenUTXOs)
    }
    
    public func calculateUnspentOutputBalances() throws -> UnspentOutputBalances {
        let partition = partitionUnspentOutputs()
        let bchTotal = try listUTXOs().sumSatoshi { try Satoshi($0.value) }
        let spendableBchOnlyUTXOs = sortSpendableUTXOs(by: { $0.value > $1.value })
            .filter { $0.tokenData == nil }
        let bchSpendable = try spendableBchOnlyUTXOs.sumSatoshi { try Satoshi($0.value) }
        let tokenInventory = try makeTokenInventory(from: partition.tokenUTXOs)
        return UnspentOutputBalances(bchTotal: bchTotal,
                                     bchSpendable: bchSpendable,
                                     tokenInventory: tokenInventory)
    }
    
    public func calculateTokenInventory() throws -> TokenInventory {
        let partition = partitionUnspentOutputs()
        return try makeTokenInventory(from: partition.tokenUTXOs)
    }
}

private extension Address.Book {
    func makeTokenInventory(from utxos: Set<Transaction.Output.Unspent>) throws -> TokenInventory {
        var fungibleAmountsByCategory: [CashTokens.CategoryID: UInt64] = .init()
        var nonFungibleTokensByGroup: [TokenInventory.NonFungibleTokenGroup: Int] = .init()
        for utxo in utxos {
            guard let tokenData = utxo.tokenData else { continue }
            if let amount = tokenData.amount {
                let current = fungibleAmountsByCategory[tokenData.category] ?? 0
                fungibleAmountsByCategory[tokenData.category] = try addTokenAmounts(current, amount)
            }
            if let nonFungibleToken = tokenData.nft {
                let group = TokenInventory.NonFungibleTokenGroup(category: tokenData.category,
                                                                 commitment: nonFungibleToken.commitment,
                                                                 capability: nonFungibleToken.capability)
                nonFungibleTokensByGroup[group, default: 0] += 1
            }
        }
        return TokenInventory(fungibleAmountsByCategory: fungibleAmountsByCategory,
                              nonFungibleTokensByGroup: nonFungibleTokensByGroup)
    }
    
    func addTokenAmounts(_ left: UInt64, _ right: UInt64) throws -> UInt64 {
        let (sum, overflow) = left.addingReportingOverflow(right)
        if overflow {
            throw Error.paymentExceedsMaximumAmount
        }
        return sum
    }
}
