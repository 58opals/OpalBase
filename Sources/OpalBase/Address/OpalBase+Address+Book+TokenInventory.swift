// OpalBase+Address+Book+TokenInventory.swift

import Foundation

extension _OpalBase.Address.Book {
    public struct TokenInventory: Sendable, Equatable {
        public struct NonFungibleTokenGroup: Hashable, Sendable {
            public let category: OpalBase.CashTokens.CategoryID
            public let commitment: Data
            public let capability: OpalBase.CashTokens.NFT.Capability
            
            public init(category: OpalBase.CashTokens.CategoryID,
                        commitment: Data,
                        capability: OpalBase.CashTokens.NFT.Capability) {
                self.category = category
                self.commitment = commitment
                self.capability = capability
            }
        }
        
        public let fungibleAmountsByCategory: [OpalBase.CashTokens.CategoryID: UInt64]
        public let nonFungibleTokensByGroup: [NonFungibleTokenGroup: Int]
        
        public init(fungibleAmountsByCategory: [OpalBase.CashTokens.CategoryID: UInt64],
                    nonFungibleTokensByGroup: [NonFungibleTokenGroup: Int]) {
            self.fungibleAmountsByCategory = fungibleAmountsByCategory
            self.nonFungibleTokensByGroup = nonFungibleTokensByGroup
        }
    }
}

extension _OpalBase.Address.Book {
    public func partitionUnspentOutputs() -> UnspentOutputPartition {
        let utxos = listUTXOs()
        var bchOnlyUTXOs: Set<OpalBase.Transaction.Output.Unspent> = .init()
        var tokenUTXOs: Set<OpalBase.Transaction.Output.Unspent> = .init()
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
    
    public func calculateUnspentOutputBalances() async throws -> UnspentOutputBalances {
        let utxos = listUTXOs()
        var tokenUTXOs: Set<OpalBase.Transaction.Output.Unspent> = .init()
        tokenUTXOs.reserveCapacity(utxos.count)
        
        var bchTotal: OpalBase.Satoshi = try .init(0)
        for utxo in utxos {
            bchTotal = try bchTotal + OpalBase.Satoshi(utxo.value)
            if utxo.tokenData != nil {
                tokenUTXOs.insert(utxo)
            }
        }
        let spendableBchOnlyUTXOs = await sortSpendableUTXOs(by: { $0.value > $1.value })
            .filter { $0.tokenData == nil }
        let bchSpendable = try spendableBchOnlyUTXOs.sumSatoshi { try OpalBase.Satoshi($0.value) }
        let tokenInventory = try makeTokenInventory(from: tokenUTXOs)
        return UnspentOutputBalances(bchTotal: bchTotal,
                                     bchSpendable: bchSpendable,
                                     tokenInventory: tokenInventory)
    }
    
    public func calculateTokenInventory() throws -> TokenInventory {
        let partition = partitionUnspentOutputs()
        return try makeTokenInventory(from: partition.tokenUTXOs)
    }
}

private extension _OpalBase.Address.Book {
    func makeTokenInventory(from utxos: Set<OpalBase.Transaction.Output.Unspent>) throws -> TokenInventory {
        var fungibleAmountsByCategory: [OpalBase.CashTokens.CategoryID: UInt64] = .init()
        var nonFungibleTokensByGroup: [TokenInventory.NonFungibleTokenGroup: Int] = .init()
        for utxo in utxos {
            guard let tokenData = utxo.tokenData else { continue }
            if let amount = tokenData.amount {
                let current = fungibleAmountsByCategory[tokenData.category] ?? 0
                fungibleAmountsByCategory[tokenData.category] = try current.addOrThrow(
                    amount,
                    overflowError: Error.paymentExceedsMaximumAmount
                )
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
}
