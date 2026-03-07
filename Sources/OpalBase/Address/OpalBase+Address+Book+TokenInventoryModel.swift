// OpalBase+Address+Book+TokenInventoryModel.swift

import Foundation

extension _OpalBase.Address.Book {
    public struct TokenInventoryModel: Sendable, Equatable {
        public struct NonFungibleTokenGroup: Hashable, Sendable {
            public let category: OpalBase.CashTokens.CategoryIDModel
            public let commitment: Data
            public let capability: OpalBase.CashTokens.NFTModel.Capability
            
            public init(category: OpalBase.CashTokens.CategoryIDModel,
                        commitment: Data,
                        capability: OpalBase.CashTokens.NFTModel.Capability) {
                self.category = category
                self.commitment = commitment
                self.capability = capability
            }
        }
        
        public let fungibleAmountsByCategory: [OpalBase.CashTokens.CategoryIDModel: UInt64]
        public let nonFungibleTokensByGroup: [NonFungibleTokenGroup: Int]
        
        public init(fungibleAmountsByCategory: [OpalBase.CashTokens.CategoryIDModel: UInt64],
                    nonFungibleTokensByGroup: [NonFungibleTokenGroup: Int]) {
            self.fungibleAmountsByCategory = fungibleAmountsByCategory
            self.nonFungibleTokensByGroup = nonFungibleTokensByGroup
        }
    }
    
    public struct UnspentOutputPartitionModel: Sendable, Equatable {
        public let bchOnlyUTXOs: Set<OpalBase.Transaction.OutputModel.Unspent>
        public let tokenUTXOs: Set<OpalBase.Transaction.OutputModel.Unspent>
        
        public init(bchOnlyUTXOs: Set<OpalBase.Transaction.OutputModel.Unspent>,
                    tokenUTXOs: Set<OpalBase.Transaction.OutputModel.Unspent>) {
            self.bchOnlyUTXOs = bchOnlyUTXOs
            self.tokenUTXOs = tokenUTXOs
        }
    }
    
    public struct UnspentOutputBalancesModel: Sendable, Equatable {
        public let bchTotal: OpalBase.Satoshi
        public let bchSpendable: OpalBase.Satoshi
        public let tokenInventory: TokenInventoryModel
        
        public init(bchTotal: OpalBase.Satoshi,
                    bchSpendable: OpalBase.Satoshi,
                    tokenInventory: TokenInventoryModel) {
            self.bchTotal = bchTotal
            self.bchSpendable = bchSpendable
            self.tokenInventory = tokenInventory
        }
    }
}

extension _OpalBase.Address.Book {
    public func partitionUnspentOutputs() -> UnspentOutputPartitionModel {
        let utxos = listUTXOs()
        var bchOnlyUTXOs: Set<OpalBase.Transaction.OutputModel.Unspent> = .init()
        var tokenUTXOs: Set<OpalBase.Transaction.OutputModel.Unspent> = .init()
        for utxo in utxos {
            if utxo.tokenData == nil {
                bchOnlyUTXOs.insert(utxo)
            } else {
                tokenUTXOs.insert(utxo)
            }
        }
        return UnspentOutputPartitionModel(bchOnlyUTXOs: bchOnlyUTXOs,
                                      tokenUTXOs: tokenUTXOs)
    }
    
    public func calculateUnspentOutputBalances() async throws -> UnspentOutputBalancesModel {
        let utxos = listUTXOs()
        var tokenUTXOs: Set<OpalBase.Transaction.OutputModel.Unspent> = .init()
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
        return UnspentOutputBalancesModel(bchTotal: bchTotal,
                                     bchSpendable: bchSpendable,
                                     tokenInventory: tokenInventory)
    }
    
    public func calculateTokenInventory() throws -> TokenInventoryModel {
        let partition = partitionUnspentOutputs()
        return try makeTokenInventory(from: partition.tokenUTXOs)
    }
}

private extension _OpalBase.Address.Book {
    func makeTokenInventory(from utxos: Set<OpalBase.Transaction.OutputModel.Unspent>) throws -> TokenInventoryModel {
        var fungibleAmountsByCategory: [OpalBase.CashTokens.CategoryIDModel: UInt64] = .init()
        var nonFungibleTokensByGroup: [TokenInventoryModel.NonFungibleTokenGroup: Int] = .init()
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
                let group = TokenInventoryModel.NonFungibleTokenGroup(category: tokenData.category,
                                                                 commitment: nonFungibleToken.commitment,
                                                                 capability: nonFungibleToken.capability)
                nonFungibleTokensByGroup[group, default: 0] += 1
            }
        }
        return TokenInventoryModel(fungibleAmountsByCategory: fungibleAmountsByCategory,
                              nonFungibleTokensByGroup: nonFungibleTokensByGroup)
    }
}
