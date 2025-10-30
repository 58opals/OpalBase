// Address+Book+Snapshot.swift

import Foundation
import CryptoKit

extension Address.Book {
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
            public let transactionHash: String
            public let height: Int
            public let fee: UInt?
            public let scriptHashes: [String]
            public let firstSeenAt: Date
            public let lastUpdatedAt: Date
            public let status: History.Transaction.Status
            public let confirmationHeight: UInt64?
            public let confirmedAt: Date?
            
            public init(transactionHash: String,
                        height: Int,
                        fee: UInt?,
                        scriptHashes: [String],
                        firstSeenAt: Date,
                        lastUpdatedAt: Date,
                        status: History.Transaction.Status,
                        confirmationHeight: UInt64?,
                        confirmedAt: Date?) {
                self.transactionHash = transactionHash
                self.height = height
                self.fee = fee
                self.scriptHashes = scriptHashes
                self.firstSeenAt = firstSeenAt
                self.lastUpdatedAt = lastUpdatedAt
                self.status = status
                self.confirmationHeight = confirmationHeight
                self.confirmedAt = confirmedAt
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

extension Address.Book.Snapshot {
    enum Error: Swift.Error {
        case missingCombinedData
    }
}

extension Address.Book.Snapshot: Sendable {}
extension Address.Book.Snapshot.Entry: Sendable {}
extension Address.Book.Snapshot.UTXO: Sendable {}
extension Address.Book.Snapshot.Transaction: Sendable {}

extension Address.Book {
    public func makeSnapshot() -> Snapshot {
        let receiving = receivingEntries.map { entry in
            Snapshot.Entry(usage: entry.derivationPath.usage,
                           index: entry.derivationPath.index,
                           isUsed: entry.isUsed,
                           balance: entry.cache.balance?.uint64,
                           lastUpdated: entry.cache.lastUpdated)
        }
        let change = changeEntries.map { entry in
            Snapshot.Entry(usage: entry.derivationPath.usage,
                           index: entry.derivationPath.index,
                           isUsed: entry.isUsed,
                           balance: entry.cache.balance?.uint64,
                           lastUpdated: entry.cache.lastUpdated)
        }
        
        let utxoSnaps = utxos.map {
            Snapshot.UTXO(value: $0.value,
                          lockingScript: $0.lockingScript.hexadecimalString,
                          transactionHash: $0.previousTransactionHash.naturalOrder.hexadecimalString,
                          outputIndex: $0.previousTransactionOutputIndex)
        }
        
        let transactionSnaps = transactionHistories.values.map { record in
            Snapshot.Transaction(transactionHash: record.transactionHash.naturalOrder.hexadecimalString,
                                 height: record.height,
                                 fee: record.fee,
                                 scriptHashes: Array(record.scriptHashes),
                                 firstSeenAt: record.firstSeenAt,
                                 lastUpdatedAt: record.lastUpdatedAt,
                                 status: record.status,
                                 confirmationHeight: record.confirmationHeight,
                                 confirmedAt: record.confirmedAt)
        }
        
        return Snapshot(receivingEntries: receiving,
                        changeEntries: change,
                        utxos: utxoSnaps,
                        transactions: transactionSnaps)
    }
    
    public func applySnapshot(_ snapshot: Snapshot) throws {
        try apply(entrySnapshots: snapshot.receivingEntries, usage: .receiving)
        try apply(entrySnapshots: snapshot.changeEntries, usage: .change)
        
        let restoredUTXOs = try snapshot.utxos.map {
            Transaction.Output.Unspent(value: $0.value,
                                       lockingScript: try Data(hexString: $0.lockingScript),
                                       previousTransactionHash: .init(naturalOrder: try Data(hexString: $0.transactionHash)),
                                       previousTransactionOutputIndex: $0.outputIndex)
        }
        utxos = Set(restoredUTXOs)
        
        transactionHistories.removeAll()
        scriptHashToTransactions.removeAll()
        
        for transaction in snapshot.transactions {
            let hash = Transaction.Hash(naturalOrder: try Data(hexString: transaction.transactionHash))
            let record = History.Transaction.Record(transactionHash: hash,
                                                    height: transaction.height,
                                                    fee: transaction.fee,
                                                    scriptHashes: Set(transaction.scriptHashes),
                                                    firstSeenAt: transaction.firstSeenAt,
                                                    lastUpdatedAt: transaction.lastUpdatedAt,
                                                    status: transaction.status,
                                                    confirmationHeight: transaction.confirmationHeight,
                                                    confirmedAt: transaction.confirmedAt)
            transactionHistories[hash] = record
            
            for scriptHash in transaction.scriptHashes {
                scriptHashToTransactions[scriptHash, default: .init()].insert(hash)
            }
        }
    }
    
    private func apply(entrySnapshots: [Snapshot.Entry], usage: DerivationPath.Usage) throws {
        for snap in entrySnapshots {
            while listEntries(for: usage).count <= snap.index {
                try generateEntry(for: usage, isUsed: false)
            }
            
            switch usage {
            case .receiving:
                var entry = receivingEntries[Int(snap.index)]
                entry.isUsed = snap.isUsed
                entry.cache.balance = snap.balance.flatMap { try? Satoshi($0) }
                entry.cache.lastUpdated = snap.lastUpdated
                receivingEntries[Int(snap.index)] = entry
                addressToEntry[entry.address] = entry
                derivationPathToAddress[entry.derivationPath] = entry.address
            case .change:
                var entry = changeEntries[Int(snap.index)]
                entry.isUsed = snap.isUsed
                entry.cache.balance = snap.balance.flatMap { try? Satoshi($0) }
                entry.cache.lastUpdated = snap.lastUpdated
                changeEntries[Int(snap.index)] = entry
                addressToEntry[entry.address] = entry
                derivationPathToAddress[entry.derivationPath] = entry.address
            }
        }
    }
}

extension Address.Book {
    public func saveSnapshot(to url: URL, using key: SymmetricKey? = nil) throws {
        let data = try JSONEncoder().encode(makeSnapshot())
        let output: Data
        
        if let key {
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { throw Snapshot.Error.missingCombinedData }
            output = combined
        } else {
            output = data
        }
        
        try output.write(to: url)
    }
    
    public func loadSnapshot(from url: URL, using key: SymmetricKey? = nil) throws {
        let data = try Data(contentsOf: url)
        let input: Data
        
        if let key {
            let sealed = try AES.GCM.SealedBox(combined: data)
            input = try AES.GCM.open(sealed, using: key)
        } else {
            input = data
        }
        
        let snap = try JSONDecoder().decode(Snapshot.self, from: input)
        try applySnapshot(snap)
    }
}
