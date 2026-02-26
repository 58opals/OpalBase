// AddressModel+BookActor+TokenInventoryModel.swift

import Foundation

extension AddressModel.BookActor {
    public struct TokenInventoryModel: Sendable, Equatable {
        public struct NonFungibleTokenGroup: Hashable, Sendable {
            public let category: CashTokensModel.CategoryIDModel
            public let commitment: Data
            public let capability: CashTokensModel.NFTModel.Capability
            
            public init(category: CashTokensModel.CategoryIDModel,
                        commitment: Data,
                        capability: CashTokensModel.NFTModel.Capability) {
                self.category = category
                self.commitment = commitment
                self.capability = capability
            }
        }
        
        public let fungibleAmountsByCategory: [CashTokensModel.CategoryIDModel: UInt64]
        public let nonFungibleTokensByGroup: [NonFungibleTokenGroup: Int]
        
        public init(fungibleAmountsByCategory: [CashTokensModel.CategoryIDModel: UInt64],
                    nonFungibleTokensByGroup: [NonFungibleTokenGroup: Int]) {
            self.fungibleAmountsByCategory = fungibleAmountsByCategory
            self.nonFungibleTokensByGroup = nonFungibleTokensByGroup
        }
    }
    
    public struct UnspentOutputPartitionModel: Sendable, Equatable {
        public let bchOnlyUTXOs: Set<TransactionModel.OutputModel.UnspentModel>
        public let tokenUTXOs: Set<TransactionModel.OutputModel.UnspentModel>
        
        public init(bchOnlyUTXOs: Set<TransactionModel.OutputModel.UnspentModel>,
                    tokenUTXOs: Set<TransactionModel.OutputModel.UnspentModel>) {
            self.bchOnlyUTXOs = bchOnlyUTXOs
            self.tokenUTXOs = tokenUTXOs
        }
    }
    
    public struct UnspentOutputBalancesModel: Sendable, Equatable {
        public let bchTotal: SatoshiModel
        public let bchSpendable: SatoshiModel
        public let tokenInventory: TokenInventoryModel
        
        public init(bchTotal: SatoshiModel,
                    bchSpendable: SatoshiModel,
                    tokenInventory: TokenInventoryModel) {
            self.bchTotal = bchTotal
            self.bchSpendable = bchSpendable
            self.tokenInventory = tokenInventory
        }
    }
}

extension AddressModel.BookActor {
    public func partitionUnspentOutputs() -> UnspentOutputPartitionModel {
        let utxos = listUTXOs()
        var bchOnlyUTXOs: Set<TransactionModel.OutputModel.UnspentModel> = .init()
        var tokenUTXOs: Set<TransactionModel.OutputModel.UnspentModel> = .init()
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
        var tokenUTXOs: Set<TransactionModel.OutputModel.UnspentModel> = .init()
        tokenUTXOs.reserveCapacity(utxos.count)
        
        var bchTotal: SatoshiModel = try .init(0)
        for utxo in utxos {
            bchTotal = try bchTotal + SatoshiModel(utxo.value)
            if utxo.tokenData != nil {
                tokenUTXOs.insert(utxo)
            }
        }
        let spendableBchOnlyUTXOs = await sortSpendableUTXOs(by: { $0.value > $1.value })
            .filter { $0.tokenData == nil }
        let bchSpendable = try spendableBchOnlyUTXOs.sumSatoshi { try SatoshiModel($0.value) }
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

private extension AddressModel.BookActor {
    func makeTokenInventory(from utxos: Set<TransactionModel.OutputModel.UnspentModel>) throws -> TokenInventoryModel {
        var fungibleAmountsByCategory: [CashTokensModel.CategoryIDModel: UInt64] = .init()
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
