// OpalBase+Address+Book+SnapshotModel.swift

import Foundation

extension _OpalBase.Address.Book {
    public typealias AddressBookSnapshotTransactionHistory = OpalBase.Transaction.HistoryModel

    public struct SnapshotModel: Codable, Equatable, Hashable, Sendable {
        public struct Entry: Codable, Equatable, Hashable, Sendable {
            public let usage: OpalBase.DerivationPath.UsageModel
            public let index: UInt32
            public let isUsed: Bool
            public let isReserved: Bool
            public let balance: UInt64?
            public let lastUpdated: Date?

            public init(usage: OpalBase.DerivationPath.UsageModel,
                        index: UInt32,
                        isUsed: Bool,
                        isReserved: Bool,
                        balance: UInt64?,
                        lastUpdated: Date?) {
                self.usage = usage
                self.index = index
                self.isUsed = isUsed
                self.isReserved = isReserved
                self.balance = balance
                self.lastUpdated = lastUpdated
            }
        }

        public struct Transaction: Codable, Equatable, Hashable, Sendable {
            public struct MerkleProof: Codable, Equatable, Hashable, Sendable {
                public let blockHeight: UInt32
                public let position: UInt32
                public let branch: [String]
                public let blockHash: String?

                public init(blockHeight: UInt32,
                            position: UInt32,
                            branch: [String],
                            blockHash: String?) {
                    self.blockHeight = blockHeight
                    self.position = position
                    self.branch = branch
                    self.blockHash = blockHash
                }
            }

            public let transactionHash: String
            public let height: Int
            public let fee: UInt64?
            public let scriptHashes: [String]
            public let firstSeenAt: Date
            public let lastUpdatedAt: Date
            public let status: AddressBookSnapshotTransactionHistory.Status
            public let confirmationHeight: UInt64?
            public let confirmedAt: Date?
            public let verificationStatus: AddressBookSnapshotTransactionHistory.Status.Verification
            public let merkleProof: MerkleProof?
            public let lastVerifiedHeight: UInt32?
            public let lastCheckedAt: Date?
            public let fungibleTokenDeltasByCategory: [OpalBase.CashTokens.CategoryIDModel: Int64]?
            public let nonFungibleTokenAdditions: [OpalBase.CashTokens.TokenData]?
            public let nonFungibleTokenRemovals: [OpalBase.CashTokens.TokenData]?
            public let bitcoinCashLockedInTokenOutputDelta: Int64?

            public init(transactionHash: String,
                        height: Int,
                        fee: UInt64?,
                        scriptHashes: [String],
                        firstSeenAt: Date,
                        lastUpdatedAt: Date,
                        status: AddressBookSnapshotTransactionHistory.Status,
                        confirmationHeight: UInt64?,
                        confirmedAt: Date?,
                        verificationStatus: AddressBookSnapshotTransactionHistory.Status.Verification,
                        merkleProof: MerkleProof?,
                        lastVerifiedHeight: UInt32?,
                        lastCheckedAt: Date?,
                        fungibleTokenDeltasByCategory: [OpalBase.CashTokens.CategoryIDModel: Int64]? = nil,
                        nonFungibleTokenAdditions: [OpalBase.CashTokens.TokenData]? = nil,
                        nonFungibleTokenRemovals: [OpalBase.CashTokens.TokenData]? = nil,
                        bitcoinCashLockedInTokenOutputDelta: Int64? = nil) {
                self.transactionHash = transactionHash
                self.height = height
                self.fee = fee
                self.scriptHashes = scriptHashes
                self.firstSeenAt = firstSeenAt
                self.lastUpdatedAt = lastUpdatedAt
                self.status = status
                self.confirmationHeight = confirmationHeight
                self.confirmedAt = confirmedAt
                self.verificationStatus = verificationStatus
                self.merkleProof = merkleProof
                self.lastVerifiedHeight = lastVerifiedHeight
                self.lastCheckedAt = lastCheckedAt
                self.fungibleTokenDeltasByCategory = fungibleTokenDeltasByCategory
                self.nonFungibleTokenAdditions = nonFungibleTokenAdditions
                self.nonFungibleTokenRemovals = nonFungibleTokenRemovals
                self.bitcoinCashLockedInTokenOutputDelta = bitcoinCashLockedInTokenOutputDelta
            }
        }

        public let receivingEntries: [Entry]
        public let changeEntries: [Entry]
        public let utxos: [UTXO]
        public let transactions: [Transaction]

        public init(receivingEntries: [Entry],
                    changeEntries: [Entry],
                    utxos: [UTXO],
                    transactions: [Transaction]) {
            self.receivingEntries = receivingEntries
            self.changeEntries = changeEntries
            self.utxos = utxos
            self.transactions = transactions
        }
    }
}
