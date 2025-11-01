// Address+Book+Snapshot.swift

import Foundation

extension Address.Book {
    public typealias AddressBookSnapshotTransactionHistory = Transaction.History
    
    public struct Snapshot: Codable {
        public struct Entry: Codable {
            public let usage: DerivationPath.Usage
            public let index: UInt32
            public let isUsed: Bool
            public let balance: UInt64?
            public let lastUpdated: Date?
            
            public init(usage: DerivationPath.Usage,
                        index: UInt32,
                        isUsed: Bool,
                        balance: UInt64?,
                        lastUpdated: Date?) {
                self.usage = usage
                self.index = index
                self.isUsed = isUsed
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
            public let verificationStatus: AddressBookSnapshotTransactionHistory.VerificationStatus
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
                        verificationStatus: AddressBookSnapshotTransactionHistory.VerificationStatus,
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

extension Address.Book.Snapshot: Sendable {}
extension Address.Book.Snapshot.Entry: Sendable {}
extension Address.Book.Snapshot.UTXO: Sendable {}
extension Address.Book.Snapshot.Transaction: Sendable {}
extension Address.Book.Snapshot.Transaction.MerkleProof: Sendable {}

extension Address.Book {
    public func makeSnapshot() -> Snapshot {
        let receiving = inventory.entries(for: .receiving).map { entry in
            Snapshot.Entry(usage: entry.derivationPath.usage,
                           index: entry.derivationPath.index,
                           isUsed: entry.isUsed,
                           balance: entry.cache.balance?.uint64,
                           lastUpdated: entry.cache.lastUpdated)
        }
        let change = inventory.entries(for: .change).map { entry in
            Snapshot.Entry(usage: entry.derivationPath.usage,
                           index: entry.derivationPath.index,
                           isUsed: entry.isUsed,
                           balance: entry.cache.balance?.uint64,
                           lastUpdated: entry.cache.lastUpdated)
        }
        
        let utxoSnaps = utxoStore.list().map {
            Snapshot.UTXO(value: $0.value,
                          lockingScript: $0.lockingScript.hexadecimalString,
                          transactionHash: $0.previousTransactionHash.naturalOrder.hexadecimalString,
                          outputIndex: $0.previousTransactionOutputIndex)
        }
        
        let transactionSnaps = transactionLog.listRecords().map { record in
            let proof = record.merkleProof.map { proof in
                Snapshot.Transaction.MerkleProof(blockHeight: proof.blockHeight,
                                                 position: proof.position,
                                                 branch: proof.branch.map { $0.hexadecimalString },
                                                 blockHash: proof.blockHash?.hexadecimalString)
            }
            return Snapshot.Transaction(transactionHash: record.transactionHash.naturalOrder.hexadecimalString,
                                        height: record.height,
                                        fee: record.fee,
                                        scriptHashes: Array(record.scriptHashes),
                                        firstSeenAt: record.firstSeenAt,
                                        lastUpdatedAt: record.lastUpdatedAt,
                                        status: record.status,
                                        confirmationHeight: record.confirmationHeight,
                                        confirmedAt: record.confirmedAt,
                                        verificationStatus: record.verificationStatus,
                                        merkleProof: proof,
                                        lastVerifiedHeight: record.lastVerifiedHeight,
                                        lastCheckedAt: record.lastCheckedAt)
        }
        
        return Snapshot(receivingEntries: receiving,
                        changeEntries: change,
                        utxos: utxoSnaps,
                        transactions: transactionSnaps)
    }
    
    public func applySnapshot(_ snapshot: Snapshot) async throws {
        try await apply(entrySnapshots: snapshot.receivingEntries, usage: .receiving)
        try await apply(entrySnapshots: snapshot.changeEntries, usage: .change)
        
        let restoredUTXOs = try snapshot.utxos.map {
            Transaction.Output.Unspent(value: $0.value,
                                       lockingScript: try Data(hexadecimalString: $0.lockingScript),
                                       previousTransactionHash: .init(naturalOrder: try Data(hexadecimalString: $0.transactionHash)),
                                       previousTransactionOutputIndex: $0.outputIndex)
        }
        
        utxoStore.replace(with: Set(restoredUTXOs))
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
            let record = Transaction.History.Record(transactionHash: hash,
                                                    height: transaction.height,
                                                    fee: transaction.fee,
                                                    scriptHashes: Set(transaction.scriptHashes),
                                                    firstSeenAt: transaction.firstSeenAt,
                                                    lastUpdatedAt: transaction.lastUpdatedAt,
                                                    status: transaction.status,
                                                    confirmationHeight: transaction.confirmationHeight,
                                                    confirmedAt: transaction.confirmedAt,
                                                    verificationStatus: transaction.verificationStatus,
                                                    merkleProof: proof,
                                                    lastVerifiedHeight: transaction.lastVerifiedHeight,
                                                    lastCheckedAt: transaction.lastCheckedAt)
            transactionLog.store(record)
        }
    }
    
    private func apply(entrySnapshots: [Snapshot.Entry], usage: DerivationPath.Usage) async throws {
        for snap in entrySnapshots {
            while listEntries(for: usage).count <= snap.index {
                try await generateEntry(for: usage, isUsed: false)
            }
            
            switch usage {
            case .receiving:
                inventory.updateEntry(at: Int(snap.index), usage: .receiving) { entry in
                    entry.isUsed = snap.isUsed
                    entry.cache.balance = snap.balance.flatMap { try? Satoshi($0) }
                    entry.cache.lastUpdated = snap.lastUpdated
                }
            case .change:
                inventory.updateEntry(at: Int(snap.index), usage: .change) { entry in
                    entry.isUsed = snap.isUsed
                    entry.cache.balance = snap.balance.flatMap { try? Satoshi($0) }
                    entry.cache.lastUpdated = snap.lastUpdated
                }
            }
        }
    }
}
