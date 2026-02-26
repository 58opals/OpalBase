// AddressModel+BookActor+SnapshotModel.swift

import Foundation

extension AddressModel.BookActor {
    public typealias AddressBookSnapshotTransactionHistory = TransactionModel.HistoryModel

    public struct SnapshotModel: Codable, Equatable, Hashable, Sendable {
        public struct EntryModel: Codable, Equatable, Hashable, Sendable {
            public let usage: DerivationPathModel.UsageModel
            public let index: UInt32
            public let isUsed: Bool
            public let isReserved: Bool
            public let balance: UInt64?
            public let lastUpdated: Date?

            public init(usage: DerivationPathModel.UsageModel,
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

        public struct TransactionModel: Codable, Equatable, Hashable, Sendable {
            public struct MerkleProofModel: Codable, Equatable, Hashable, Sendable {
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
            public let status: AddressBookSnapshotTransactionHistory.StatusModel
            public let confirmationHeight: UInt64?
            public let confirmedAt: Date?
            public let verificationStatus: AddressBookSnapshotTransactionHistory.StatusModel.Verification
            public let merkleProof: MerkleProofModel?
            public let lastVerifiedHeight: UInt32?
            public let lastCheckedAt: Date?
            public let fungibleTokenDeltasByCategory: [CashTokensModel.CategoryIDModel: Int64]?
            public let nonFungibleTokenAdditions: [CashTokensModel.TokenData]?
            public let nonFungibleTokenRemovals: [CashTokensModel.TokenData]?
            public let bitcoinCashLockedInTokenOutputDelta: Int64?

            public init(transactionHash: String,
                        height: Int,
                        fee: UInt64?,
                        scriptHashes: [String],
                        firstSeenAt: Date,
                        lastUpdatedAt: Date,
                        status: AddressBookSnapshotTransactionHistory.StatusModel,
                        confirmationHeight: UInt64?,
                        confirmedAt: Date?,
                        verificationStatus: AddressBookSnapshotTransactionHistory.StatusModel.Verification,
                        merkleProof: MerkleProofModel?,
                        lastVerifiedHeight: UInt32?,
                        lastCheckedAt: Date?,
                        fungibleTokenDeltasByCategory: [CashTokensModel.CategoryIDModel: Int64]? = nil,
                        nonFungibleTokenAdditions: [CashTokensModel.TokenData]? = nil,
                        nonFungibleTokenRemovals: [CashTokensModel.TokenData]? = nil,
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

        public let receivingEntries: [EntryModel]
        public let changeEntries: [EntryModel]
        public let utxos: [UTXOModel]
        public let transactions: [TransactionModel]

        public init(receivingEntries: [EntryModel],
                    changeEntries: [EntryModel],
                    utxos: [UTXOModel],
                    transactions: [TransactionModel]) {
            self.receivingEntries = receivingEntries
            self.changeEntries = changeEntries
            self.utxos = utxos
            self.transactions = transactions
        }
    }
}
