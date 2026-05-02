// OpalBase+Account+Snapshot.swift

import Foundation

extension _OpalBase.Account {
    public struct Snapshot: Codable {
        public struct AddressBook: Codable, Equatable, Hashable, Sendable {
            public struct Entry: Codable, Equatable, Hashable, Sendable {
                public let usage: OpalBase.Key.DerivationPath.Usage
                public let index: UInt32
                public let isUsed: Bool
                public let isReserved: Bool
                public let balance: UInt64?
                public let lastUpdated: Date?

                public init(
                    usage: OpalBase.Key.DerivationPath.Usage,
                    index: UInt32,
                    isUsed: Bool,
                    isReserved: Bool,
                    balance: UInt64?,
                    lastUpdated: Date?
                ) {
                    self.usage = usage
                    self.index = index
                    self.isUsed = isUsed
                    self.isReserved = isReserved
                    self.balance = balance
                    self.lastUpdated = lastUpdated
                }

                init(_ entry: OpalBase.Address.Book.Snapshot.Entry) {
                    self.init(
                        usage: entry.usage,
                        index: entry.index,
                        isUsed: entry.isUsed,
                        isReserved: entry.isReserved,
                        balance: entry.balance,
                        lastUpdated: entry.lastUpdated
                    )
                }

                var addressBookEntry: OpalBase.Address.Book.Snapshot.Entry {
                    .init(
                        usage: usage,
                        index: index,
                        isUsed: isUsed,
                        isReserved: isReserved,
                        balance: balance,
                        lastUpdated: lastUpdated
                    )
                }
            }

            public struct UTXO: Codable, Equatable, Hashable, Sendable {
                public let value: UInt64
                public let lockingScript: String
                public let tokenCategory: String?
                public let tokenAmount: UInt64?
                public let nftCapability: OpalBase.CashTokens.NFT.Capability?
                public let nftCommitment: String?
                public let transactionHash: String
                public let outputIndex: UInt32

                public init(
                    value: UInt64,
                    lockingScript: String,
                    tokenCategory: String?,
                    tokenAmount: UInt64?,
                    nftCapability: OpalBase.CashTokens.NFT.Capability?,
                    nftCommitment: String?,
                    transactionHash: String,
                    outputIndex: UInt32
                ) {
                    self.value = value
                    self.lockingScript = lockingScript
                    self.tokenCategory = tokenCategory
                    self.tokenAmount = tokenAmount
                    self.nftCapability = nftCapability
                    self.nftCommitment = nftCommitment
                    self.transactionHash = transactionHash
                    self.outputIndex = outputIndex
                }

                init(_ utxo: OpalBase.Address.Book.Snapshot.UTXO) {
                    self.init(
                        value: utxo.value,
                        lockingScript: utxo.lockingScript,
                        tokenCategory: utxo.tokenCategory,
                        tokenAmount: utxo.tokenAmount,
                        nftCapability: utxo.nftCapability,
                        nftCommitment: utxo.nftCommitment,
                        transactionHash: utxo.transactionHash,
                        outputIndex: utxo.outputIndex
                    )
                }

                public func makeTokenData() throws -> OpalBase.CashTokens.TokenData? {
                    try addressBookUTXO.makeTokenData()
                }

                var addressBookUTXO: OpalBase.Address.Book.Snapshot.UTXO {
                    .init(
                        value: value,
                        lockingScript: lockingScript,
                        tokenCategory: tokenCategory,
                        tokenAmount: tokenAmount,
                        nftCapability: nftCapability,
                        nftCommitment: nftCommitment,
                        transactionHash: transactionHash,
                        outputIndex: outputIndex
                    )
                }
            }

            public struct Transaction: Codable, Equatable, Hashable, Sendable {
                public struct MerkleProof: Codable, Equatable, Hashable, Sendable {
                    public let blockHeight: UInt32
                    public let position: UInt32
                    public let branch: [String]
                    public let blockHash: String?

                    public init(
                        blockHeight: UInt32,
                        position: UInt32,
                        branch: [String],
                        blockHash: String?
                    ) {
                        self.blockHeight = blockHeight
                        self.position = position
                        self.branch = branch
                        self.blockHash = blockHash
                    }

                    init(_ proof: OpalBase.Address.Book.Snapshot.Transaction.MerkleProof) {
                        self.init(
                            blockHeight: proof.blockHeight,
                            position: proof.position,
                            branch: proof.branch,
                            blockHash: proof.blockHash
                        )
                    }

                    var addressBookMerkleProof: OpalBase.Address.Book.Snapshot.Transaction.MerkleProof {
                        .init(
                            blockHeight: blockHeight,
                            position: position,
                            branch: branch,
                            blockHash: blockHash
                        )
                    }
                }

                public let transactionHash: String
                public let height: Int
                public let fee: UInt64?
                public let scriptHashes: [String]
                public let firstSeenAt: Date
                public let lastUpdatedAt: Date
                public let status: OpalBase.Transaction.History.Status
                public let confirmationHeight: UInt64?
                public let confirmedAt: Date?
                public let verificationStatus: OpalBase.Transaction.History.Status.Verification
                public let merkleProof: MerkleProof?
                public let lastVerifiedHeight: UInt32?
                public let lastCheckedAt: Date?
                public let fungibleTokenDeltasByCategory: [OpalBase.CashTokens.CategoryID: Int64]?
                public let nonFungibleTokenAdditions: [OpalBase.CashTokens.TokenData]?
                public let nonFungibleTokenRemovals: [OpalBase.CashTokens.TokenData]?
                public let bchLockedInTokenOutputDelta: Int64?

                public init(
                    transactionHash: String,
                    height: Int,
                    fee: UInt64?,
                    scriptHashes: [String],
                    firstSeenAt: Date,
                    lastUpdatedAt: Date,
                    status: OpalBase.Transaction.History.Status,
                    confirmationHeight: UInt64?,
                    confirmedAt: Date?,
                    verificationStatus: OpalBase.Transaction.History.Status.Verification,
                    merkleProof: MerkleProof?,
                    lastVerifiedHeight: UInt32?,
                    lastCheckedAt: Date?,
                    fungibleTokenDeltasByCategory: [OpalBase.CashTokens.CategoryID: Int64]? = nil,
                    nonFungibleTokenAdditions: [OpalBase.CashTokens.TokenData]? = nil,
                    nonFungibleTokenRemovals: [OpalBase.CashTokens.TokenData]? = nil,
                    bchLockedInTokenOutputDelta: Int64? = nil
                ) {
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

                init(_ transaction: OpalBase.Address.Book.Snapshot.Transaction) {
                    self.init(
                        transactionHash: transaction.transactionHash,
                        height: transaction.height,
                        fee: transaction.fee,
                        scriptHashes: transaction.scriptHashes,
                        firstSeenAt: transaction.firstSeenAt,
                        lastUpdatedAt: transaction.lastUpdatedAt,
                        status: transaction.status,
                        confirmationHeight: transaction.confirmationHeight,
                        confirmedAt: transaction.confirmedAt,
                        verificationStatus: transaction.verificationStatus,
                        merkleProof: transaction.merkleProof.map(MerkleProof.init),
                        lastVerifiedHeight: transaction.lastVerifiedHeight,
                        lastCheckedAt: transaction.lastCheckedAt,
                        fungibleTokenDeltasByCategory: transaction.fungibleTokenDeltasByCategory,
                        nonFungibleTokenAdditions: transaction.nonFungibleTokenAdditions,
                        nonFungibleTokenRemovals: transaction.nonFungibleTokenRemovals,
                        bchLockedInTokenOutputDelta: transaction.bchLockedInTokenOutputDelta
                    )
                }

                var addressBookTransaction: OpalBase.Address.Book.Snapshot.Transaction {
                    .init(
                        transactionHash: transactionHash,
                        height: height,
                        fee: fee,
                        scriptHashes: scriptHashes,
                        firstSeenAt: firstSeenAt,
                        lastUpdatedAt: lastUpdatedAt,
                        status: status,
                        confirmationHeight: confirmationHeight,
                        confirmedAt: confirmedAt,
                        verificationStatus: verificationStatus,
                        merkleProof: merkleProof?.addressBookMerkleProof,
                        lastVerifiedHeight: lastVerifiedHeight,
                        lastCheckedAt: lastCheckedAt,
                        fungibleTokenDeltasByCategory: fungibleTokenDeltasByCategory,
                        nonFungibleTokenAdditions: nonFungibleTokenAdditions,
                        nonFungibleTokenRemovals: nonFungibleTokenRemovals,
                        bchLockedInTokenOutputDelta: bchLockedInTokenOutputDelta
                    )
                }
            }

            public let receivingEntries: [Entry]
            public let changeEntries: [Entry]
            public let utxos: [UTXO]
            public let transactions: [Transaction]

            public init(
                receivingEntries: [Entry],
                changeEntries: [Entry],
                utxos: [UTXO],
                transactions: [Transaction]
            ) {
                self.receivingEntries = receivingEntries
                self.changeEntries = changeEntries
                self.utxos = utxos
                self.transactions = transactions
            }

            init(_ snapshot: OpalBase.Address.Book.Snapshot) {
                self.init(
                    receivingEntries: snapshot.receivingEntries.map(Entry.init),
                    changeEntries: snapshot.changeEntries.map(Entry.init),
                    utxos: snapshot.utxos.map(UTXO.init),
                    transactions: snapshot.transactions.map(Transaction.init)
                )
            }

            var addressBookSnapshot: OpalBase.Address.Book.Snapshot {
                .init(
                    receivingEntries: receivingEntries.map(\.addressBookEntry),
                    changeEntries: changeEntries.map(\.addressBookEntry),
                    utxos: utxos.map(\.addressBookUTXO),
                    transactions: transactions.map(\.addressBookTransaction)
                )
            }
        }

        public let purpose: OpalBase.Key.DerivationPath.Purpose
        public let coinType: OpalBase.Key.DerivationPath.CoinType
        public let accountUnhardenedIndex: UInt32
        public let addressBook: AddressBook
        
        public init(purpose: OpalBase.Key.DerivationPath.Purpose,
                    coinType: OpalBase.Key.DerivationPath.CoinType,
                    accountUnhardenedIndex: UInt32,
                    addressBook: AddressBook) {
            self.purpose = purpose
            self.coinType = coinType
            self.accountUnhardenedIndex = accountUnhardenedIndex
            self.addressBook = addressBook
        }

        init(purpose: OpalBase.Key.DerivationPath.Purpose,
             coinType: OpalBase.Key.DerivationPath.CoinType,
             accountUnhardenedIndex: UInt32,
             addressBook: OpalBase.Address.Book.Snapshot) {
            self.init(
                purpose: purpose,
                coinType: coinType,
                accountUnhardenedIndex: accountUnhardenedIndex,
                addressBook: .init(addressBook)
            )
        }
    }
}

extension _OpalBase.Account.Snapshot: Equatable, Hashable, Sendable {}

extension _OpalBase.Account {
    public func makeSnapshot() async -> Snapshot {
        let bookSnap = await addressBook.makeSnapshot()
        return Snapshot(purpose: purpose,
                        coinType: coinType,
                        accountUnhardenedIndex: self.account.unhardenedIndex,
                        addressBook: .init(bookSnap))
    }
    
    public func refresh(with snapshot: Snapshot) async throws {
        guard snapshot.purpose == purpose,
              snapshot.coinType == coinType,
              snapshot.accountUnhardenedIndex == self.account.unhardenedIndex else {
            throw Error.snapshotDoesNotMatchAccount
        }
        try await addressBook.refresh(with: snapshot.addressBook.addressBookSnapshot)
    }
}
