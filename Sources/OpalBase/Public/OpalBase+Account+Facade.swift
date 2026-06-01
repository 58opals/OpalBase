// OpalBase+Account+Facade.swift

import Foundation

extension _OpalBase.Account {
    /// A wallet-derived address exposed without the lower-level address book.
    public struct DerivedAddress: Sendable, Hashable {
        public let address: OpalBase.Address
        public let derivationPath: OpalBase.Key.DerivationPath
        public let createdAt: Date

        public init(
            address: OpalBase.Address,
            derivationPath: OpalBase.Key.DerivationPath,
            createdAt: Date
        ) {
            self.address = address
            self.derivationPath = derivationPath
            self.createdAt = createdAt
        }

        init(_ entry: OpalBase.Address.Book.Entry) {
            self.init(
                address: entry.address,
                derivationPath: entry.derivationPath,
                createdAt: entry.createdAt
            )
        }
    }

    /// Selects the BCH UTXO strategy used while preparing a spend.
    public enum CoinSelectionStrategy: Sendable {
        case greedyLargestFirst
        case branchAndBound
        case sweepAll

        var addressBookStrategy: OpalBase.Address.Book.CoinSelection {
            switch self {
            case .greedyLargestFirst:
                return .greedyLargestFirst
            case .branchAndBound:
                return .branchAndBound
            case .sweepAll:
                return .sweepAll
            }
        }
    }

    /// Controls whether ordinary BCH spends may consume token-bearing UTXOs.
    public enum TokenInputPolicy: Sendable {
        case excludeTokenUTXOs
        case allowTokenUTXOs

        var addressBookPolicy: OpalBase.Address.Book.CoinSelection.TokenSelectionPolicy {
            switch self {
            case .excludeTokenUTXOs:
                return .excludeTokenUTXOs
            case .allowTokenUTXOs:
                return .allowTokenUTXOs
            }
        }
    }

    /// Token balances grouped by CashTokens category and NFT identity.
    public struct TokenInventory: Sendable, Equatable {
        public struct NonFungibleTokenGroup: Hashable, Sendable {
            public let category: OpalBase.CashTokens.CategoryID
            public let commitment: Data
            public let capability: OpalBase.CashTokens.NFT.Capability

            public init(
                category: OpalBase.CashTokens.CategoryID,
                commitment: Data,
                capability: OpalBase.CashTokens.NFT.Capability
            ) {
                self.category = category
                self.commitment = Data(commitment)
                self.capability = capability
            }

            init(_ group: OpalBase.Address.Book.TokenInventory.NonFungibleTokenGroup) {
                self.init(
                    category: group.category,
                    commitment: group.commitment,
                    capability: group.capability
                )
            }

            var addressBookGroup: OpalBase.Address.Book.TokenInventory.NonFungibleTokenGroup {
                .init(
                    category: category,
                    commitment: commitment,
                    capability: capability
                )
            }
        }

        public let fungibleAmountsByCategory: [OpalBase.CashTokens.CategoryID: UInt64]
        public let nonFungibleTokensByGroup: [NonFungibleTokenGroup: Int]

        public init(
            fungibleAmountsByCategory: [OpalBase.CashTokens.CategoryID: UInt64],
            nonFungibleTokensByGroup: [NonFungibleTokenGroup: Int]
        ) {
            self.fungibleAmountsByCategory = fungibleAmountsByCategory
            self.nonFungibleTokensByGroup = nonFungibleTokensByGroup
        }

        init(_ inventory: OpalBase.Address.Book.TokenInventory) {
            self.init(
                fungibleAmountsByCategory: inventory.fungibleAmountsByCategory,
                nonFungibleTokensByGroup: Dictionary(
                    uniqueKeysWithValues: inventory.nonFungibleTokensByGroup.map {
                        (NonFungibleTokenGroup($0.key), $0.value)
                    }
                )
            )
        }

        var addressBookInventory: OpalBase.Address.Book.TokenInventory {
            .init(
                fungibleAmountsByCategory: fungibleAmountsByCategory,
                nonFungibleTokensByGroup: Dictionary(
                    uniqueKeysWithValues: nonFungibleTokensByGroup.map {
                        ($0.key.addressBookGroup, $0.value)
                    }
                )
            )
        }
    }

    /// Aggregated BCH and token balances for spendable wallet outputs.
    public struct UnspentOutputBalances: Sendable, Equatable {
        public let bchTotal: OpalBase.Satoshi
        public let bchSpendable: OpalBase.Satoshi
        public let tokenInventory: TokenInventory

        public init(
            bchTotal: OpalBase.Satoshi,
            bchSpendable: OpalBase.Satoshi,
            tokenInventory: TokenInventory
        ) {
            self.bchTotal = bchTotal
            self.bchSpendable = bchSpendable
            self.tokenInventory = tokenInventory
        }

        init(_ balances: OpalBase.Address.Book.UnspentOutputBalances) {
            self.init(
                bchTotal: balances.bchTotal,
                bchSpendable: balances.bchSpendable,
                tokenInventory: .init(balances.tokenInventory)
            )
        }
    }

    /// A per-address UTXO delta produced by a wallet refresh.
    public struct UTXOChangeSet: Sendable, Equatable {
        public let address: OpalBase.Address
        public let previous: [OpalBase.Transaction.Output.Unspent]
        public let updated: [OpalBase.Transaction.Output.Unspent]
        public let inserted: [OpalBase.Transaction.Output.Unspent]
        public let removed: [OpalBase.Transaction.Output.Unspent]
        public let retained: [OpalBase.Transaction.Output.Unspent]
        public let balance: OpalBase.Satoshi
        public let timestamp: Date

        public init(
            address: OpalBase.Address,
            previous: [OpalBase.Transaction.Output.Unspent],
            updated: [OpalBase.Transaction.Output.Unspent],
            inserted: [OpalBase.Transaction.Output.Unspent],
            removed: [OpalBase.Transaction.Output.Unspent],
            retained: [OpalBase.Transaction.Output.Unspent],
            balance: OpalBase.Satoshi,
            timestamp: Date
        ) {
            self.address = address
            self.previous = previous
            self.updated = updated
            self.inserted = inserted
            self.removed = removed
            self.retained = retained
            self.balance = balance
            self.timestamp = timestamp
        }

        init(_ changeSet: OpalBase.Address.Book.UTXOChangeSet) {
            self.init(
                address: changeSet.address,
                previous: changeSet.previous,
                updated: changeSet.updated,
                inserted: changeSet.inserted,
                removed: changeSet.removed,
                retained: changeSet.retained,
                balance: changeSet.balance,
                timestamp: changeSet.timestamp
            )
        }
    }

    /// Result of refreshing wallet-owned UTXOs.
    public struct UTXORefresh: Sendable, Equatable {
        public let utxosByAddress: [OpalBase.Address: [OpalBase.Transaction.Output.Unspent]]
        public let changeSets: [UTXOChangeSet]
        public let totalBalance: OpalBase.Satoshi

        public init(
            utxosByAddress: [OpalBase.Address: [OpalBase.Transaction.Output.Unspent]],
            changeSets: [UTXOChangeSet],
            totalBalance: OpalBase.Satoshi
        ) {
            self.utxosByAddress = utxosByAddress
            self.changeSets = changeSets
            self.totalBalance = totalBalance
        }

        init(_ refresh: OpalBase.Address.Book.UTXORefresh) {
            self.init(
                utxosByAddress: refresh.utxosByAddress,
                changeSets: refresh.changeSets.map(UTXOChangeSet.init),
                totalBalance: refresh.totalBalance
            )
        }
    }
}
