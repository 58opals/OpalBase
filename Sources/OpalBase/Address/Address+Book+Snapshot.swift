// Address+Book+Snapshot.swift

import Foundation

extension Address.Book {
    public typealias AddressBookSnapshotTransactionHistory = Transaction.History
    
    public struct Snapshot: Codable {
        public struct Entry: Codable {
            public let usage: DerivationPath.Usage
            public let index: UInt32
            public let isUsed: Bool
            public let isReserved: Bool
            public let balance: UInt64?
            public let lastUpdated: Date?
            
            public init(usage: DerivationPath.Usage,
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
        
        public struct UTXO: Codable {
            public let value: UInt64
            public let lockingScript: String
            public let transactionHash: String
            public let outputIndex: UInt32
            
            public init(value: UInt64,
                        lockingScript: String,
                        transactionHash: String,
                        outputIndex: UInt32) {
                self.value = value
                self.lockingScript = lockingScript
                self.transactionHash = transactionHash
                self.outputIndex = outputIndex
            }
        }
        
        public struct Transaction: Codable {
            public struct MerkleProof: Codable {
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
            public let fee: UInt?
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
            
            public init(transactionHash: String,
                        height: Int,
                        fee: UInt?,
                        scriptHashes: [String],
                        firstSeenAt: Date,
                        lastUpdatedAt: Date,
                        status: AddressBookSnapshotTransactionHistory.Status,
                        confirmationHeight: UInt64?,
                        confirmedAt: Date?,
                        verificationStatus: AddressBookSnapshotTransactionHistory.Status.Verification,
                        merkleProof: MerkleProof?,
                        lastVerifiedHeight: UInt32?,
                        lastCheckedAt: Date?) {
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

extension Address.Book.Snapshot: Equatable, Hashable, Sendable {}
extension Address.Book.Snapshot.Entry: Equatable, Hashable, Sendable {}
extension Address.Book.Snapshot.UTXO: Equatable, Hashable, Sendable {}
extension Address.Book.Snapshot.Transaction: Equatable, Hashable, Sendable {}
extension Address.Book.Snapshot.Transaction.MerkleProof: Equatable, Hashable, Sendable {}

extension Address.Book {
    init(from snapshot: Snapshot,
         rootExtendedPrivateKey: PrivateKey.Extended? = nil,
         rootExtendedPublicKey: PublicKey.Extended? = nil,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         account: DerivationPath.Account,
         gapLimit: Int = 20,
         cacheValidityDuration: TimeInterval = 10 * 60,
         spendReservationExpirationInterval: TimeInterval = 10 * 60) async throws {
        try await self.init(rootExtendedPrivateKey: rootExtendedPrivateKey,
                            rootExtendedPublicKey: rootExtendedPublicKey,
                            purpose: purpose,
                            coinType: coinType,
                            account: account,
                            gapLimit: gapLimit,
                            cacheValidityDuration: cacheValidityDuration,
                            spendReservationExpirationInterval: spendReservationExpirationInterval)
        try await refresh(with: snapshot)
    }
    
    public func makeSnapshot() -> Snapshot {
        let receiving = makeEntrySnapshots(for: .receiving)
        let change = makeEntrySnapshots(for: .change)
        
        let utxoSnaps = utxoStore.listUTXOs().map {
            Snapshot.UTXO(value: $0.value,
                          lockingScript: $0.lockingScript.hexadecimalString,
                          transactionHash: $0.previousTransactionHash.naturalOrder.hexadecimalString,
                          outputIndex: $0.previousTransactionOutputIndex)
        }
        
        let transactionSnaps = transactionLog.listRecords().map { record in
            let chainMetadata = record.chainMetadata
            let confirmationMetadata = record.confirmationMetadata
            let verificationMetadata = record.verificationMetadata
            let proof = verificationMetadata.merkleProof.map { proof in
                Snapshot.Transaction.MerkleProof(blockHeight: proof.blockHeight,
                                                 position: proof.position,
                                                 branch: proof.branch.map { $0.hexadecimalString },
                                                 blockHash: proof.blockHash?.hexadecimalString)
            }
            return Snapshot.Transaction(transactionHash: record.transactionHash.naturalOrder.hexadecimalString,
                                        height: chainMetadata.height,
                                        fee: chainMetadata.fee,
                                        scriptHashes: Array(chainMetadata.scriptHashes),
                                        firstSeenAt: chainMetadata.firstSeenAt,
                                        lastUpdatedAt: chainMetadata.lastUpdatedAt,
                                        status: record.status,
                                        confirmationHeight: confirmationMetadata.height,
                                        confirmedAt: confirmationMetadata.confirmedAt,
                                        verificationStatus: verificationMetadata.status,
                                        merkleProof: proof,
                                        lastVerifiedHeight: verificationMetadata.lastVerifiedHeight,
                                        lastCheckedAt: verificationMetadata.lastCheckedAt)
        }
        
        return Snapshot(receivingEntries: receiving,
                        changeEntries: change,
                        utxos: utxoSnaps,
                        transactions: transactionSnaps)
    }
    
    private func makeEntrySnapshots(for usage: DerivationPath.Usage) -> [Snapshot.Entry] {
        inventory.listEntries(for: usage).map { entry in
            Snapshot.Entry(usage: entry.derivationPath.usage,
                           index: entry.derivationPath.index,
                           isUsed: entry.isUsed,
                           isReserved: entry.isReserved,
                           balance: entry.cache.balance?.uint64,
                           lastUpdated: entry.cache.lastUpdated)
        }
    }
    
    public func refresh(with snapshot: Snapshot) async throws {
        try await apply(entrySnapshots: snapshot.receivingEntries, usage: .receiving)
        try await apply(entrySnapshots: snapshot.changeEntries, usage: .change)
        
        let restoredUTXOs = try snapshot.utxos.map {
            Transaction.Output.Unspent(value: $0.value,
                                       lockingScript: try Data(hexadecimalString: $0.lockingScript),
                                       previousTransactionHash: .init(naturalOrder: try Data(hexadecimalString: $0.transactionHash)),
                                       previousTransactionOutputIndex: $0.outputIndex)
        }
        
        utxoStore.replace(with: Set(restoredUTXOs))
        clearSpendReservationState()
        transactionLog.reset()
        
        for transaction in snapshot.transactions {
            let hash = Transaction.Hash(naturalOrder: try Data(hexadecimalString: transaction.transactionHash))
            let proof = try transaction.merkleProof.map { proof -> Transaction.MerkleProof in
                let branch = try proof.branch.map { try Data(hexadecimalString: $0) }
                let blockHash = try proof.blockHash.map { try Data(hexadecimalString: $0) }
                return Transaction.MerkleProof(blockHeight: proof.blockHeight,
                                               position: proof.position,
                                               branch: branch,
                                               blockHash: blockHash)
            }
            let chainMetadata = Transaction.History.Record.ChainMetadata(height: transaction.height,
                                                                         fee: transaction.fee,
                                                                         scriptHashes: Set(transaction.scriptHashes),
                                                                         firstSeenAt: transaction.firstSeenAt,
                                                                         lastUpdatedAt: transaction.lastUpdatedAt)
            let confirmationMetadata = Transaction.History.Record.ConfirmationMetadata(height: transaction.confirmationHeight,
                                                                                       confirmedAt: transaction.confirmedAt)
            let verificationMetadata = Transaction.History.Record.VerificationMetadata(status: transaction.verificationStatus,
                                                                                       merkleProof: proof,
                                                                                       lastVerifiedHeight: transaction.lastVerifiedHeight,
                                                                                       lastCheckedAt: transaction.lastCheckedAt)
            let record = Transaction.History.Record(transactionHash: hash,
                                                    status: transaction.status,
                                                    chainMetadata: chainMetadata,
                                                    confirmationMetadata: confirmationMetadata,
                                                    verificationMetadata: verificationMetadata)
            transactionLog.store(record)
        }
    }
    
    private func apply(entrySnapshots: [Snapshot.Entry], usage: DerivationPath.Usage) async throws {
        guard !entrySnapshots.isEmpty else { return }
        
        guard let highestIndex = entrySnapshots.map(\.index).max() else { return }
        
        let highestIndexValue = Int(highestIndex)
        let currentCount = inventory.countEntries(for: usage)
        if currentCount <= highestIndexValue {
            let desiredCount = highestIndexValue + 1
            let numberOfMissingEntries = desiredCount - currentCount
            if numberOfMissingEntries > 0 {
                try await generateEntries(for: usage,
                                          numberOfNewEntries: numberOfMissingEntries,
                                          isUsed: false)
            }
        }
        
        for snap in entrySnapshots {
            let restoredBalance: Satoshi?
            if let balanceValue = snap.balance {
                do {
                    restoredBalance = try Satoshi(balanceValue)
                } catch {
                    
                    throw Address.Book.Error.invalidSnapshotBalance(value: balanceValue, reason: error)
                }
            } else {
                restoredBalance = nil
            }
            
            inventory.updateEntry(at: Int(snap.index), usage: usage) { entry in
                entry.isUsed = snap.isUsed
                entry.isReserved = snap.isReserved
                entry.cache.balance = restoredBalance
                entry.cache.lastUpdated = snap.lastUpdated
            }
        }
        
        let entries = inventory.listEntries(for: usage)
        let unusedEntriesBeyondHighestIndex = entries.filter { entry in
            Int(entry.derivationPath.index) > highestIndexValue && !entry.isUsed
        }.count
        
        let numberOfMissingUnusedEntries = gapLimit - unusedEntriesBeyondHighestIndex
        if numberOfMissingUnusedEntries > 0 {
            try await generateEntries(for: usage,
                                      numberOfNewEntries: numberOfMissingUnusedEntries,
                                      isUsed: false)
        }
    }
}
