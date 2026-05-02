// OpalBase+Address+Book+Snapshot.swift

import Foundation

extension _OpalBase.Address.Book {
    typealias AddressBookSnapshotTransactionHistory = OpalBase.Transaction.History

    struct Snapshot: Codable, Equatable, Hashable, Sendable {
        struct Entry: Codable, Equatable, Hashable, Sendable {
            let usage: OpalBase.Key.DerivationPath.Usage
            let index: UInt32
            let isUsed: Bool
            let isReserved: Bool
            let balance: UInt64?
            let lastUpdated: Date?

            init(usage: OpalBase.Key.DerivationPath.Usage,
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

        struct Transaction: Codable, Equatable, Hashable, Sendable {
            struct MerkleProof: Codable, Equatable, Hashable, Sendable {
                let blockHeight: UInt32
                let position: UInt32
                let branch: [String]
                let blockHash: String?

                init(blockHeight: UInt32,
                            position: UInt32,
                            branch: [String],
                            blockHash: String?) {
                    self.blockHeight = blockHeight
                    self.position = position
                    self.branch = branch
                    self.blockHash = blockHash
                }
            }

            let transactionHash: String
            let height: Int
            let fee: UInt64?
            let scriptHashes: [String]
            let firstSeenAt: Date
            let lastUpdatedAt: Date
            let status: AddressBookSnapshotTransactionHistory.Status
            let confirmationHeight: UInt64?
            let confirmedAt: Date?
            let verificationStatus: AddressBookSnapshotTransactionHistory.Status.Verification
            let merkleProof: MerkleProof?
            let lastVerifiedHeight: UInt32?
            let lastCheckedAt: Date?
            let fungibleTokenDeltasByCategory: [OpalBase.CashTokens.CategoryID: Int64]?
            let nonFungibleTokenAdditions: [OpalBase.CashTokens.TokenData]?
            let nonFungibleTokenRemovals: [OpalBase.CashTokens.TokenData]?
            let bchLockedInTokenOutputDelta: Int64?

            init(transactionHash: String,
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
                        fungibleTokenDeltasByCategory: [OpalBase.CashTokens.CategoryID: Int64]? = nil,
                        nonFungibleTokenAdditions: [OpalBase.CashTokens.TokenData]? = nil,
                        nonFungibleTokenRemovals: [OpalBase.CashTokens.TokenData]? = nil,
                        bchLockedInTokenOutputDelta: Int64? = nil) {
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
                self.bchLockedInTokenOutputDelta = bchLockedInTokenOutputDelta
            }
        }

        let receivingEntries: [Entry]
        let changeEntries: [Entry]
        let utxos: [UTXO]
        let transactions: [Transaction]

        init(receivingEntries: [Entry],
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
