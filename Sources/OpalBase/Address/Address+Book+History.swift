// Address+Book+History.swift

import Foundation

extension Address.Book { public enum History {} }

extension Address.Book.History { public enum Transaction {} }

extension Address.Book.History.Transaction {
    public enum Status: String, Sendable, Hashable, Codable {
        case discovered
        case pending
        case confirmed
        case failed
    }
    
    public struct Entry: Sendable, Hashable {
        public let transactionHash: Transaction.Hash
        public let height: Int
        public let fee: UInt?
        
        public init(transactionHash: Transaction.Hash, height: Int, fee: UInt?) {
            self.transactionHash = transactionHash
            self.height = height
            self.fee = fee
        }
    }
    
    public struct Record: Sendable, Hashable, Equatable {
        public let transactionHash: Transaction.Hash
        public var height: Int
        public var fee: UInt?
        public var scriptHashes: Set<String>
        public let firstSeenAt: Date
        public var lastUpdatedAt: Date
        
        public var status: Status
        public var confirmationHeight: UInt64?
        public var confirmedAt: Date?
        
        public var isConfirmed: Bool { status == .confirmed }
        
        public init(transactionHash: Transaction.Hash,
                    height: Int,
                    fee: UInt?,
                    scriptHashes: Set<String>,
                    firstSeenAt: Date,
                    lastUpdatedAt: Date,
                    status: Status,
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
}

extension Address.Book.History.Transaction.Record {
    mutating func resolveUpdate(from entry: Address.Book.History.Transaction.Entry,
                                scriptHash: String,
                                timestamp: Date) {
        height = entry.height
        fee = entry.fee
        lastUpdatedAt = timestamp
        scriptHashes.insert(scriptHash)
        
        let statusUpdate = Address.Book.History.Transaction.Record.Status
            .resolve(forHeight: entry.height, previousStatus: status)
        status = statusUpdate.status
        
        if statusUpdate.status == .confirmed {
            let newHeight = statusUpdate.confirmationHeight ?? UInt64(entry.height)
            if let existingHeight = confirmationHeight, existingHeight != newHeight {
                confirmedAt = timestamp
            } else if confirmedAt == nil {
                confirmedAt = timestamp
            }
            confirmationHeight = newHeight
        } else {
            confirmationHeight = nil
            confirmedAt = nil
        }
    }
    
    static func makeRecord(for entry: Address.Book.History.Transaction.Entry,
                           scriptHash: String,
                           timestamp: Date) -> Address.Book.History.Transaction.Record {
        let statusUpdate = Address.Book.History.Transaction.Record.Status
            .resolve(forHeight: entry.height, previousStatus: nil)
        let confirmationHeight = statusUpdate.status == .confirmed
        ? (statusUpdate.confirmationHeight ?? UInt64(entry.height))
        : nil
        let confirmedAt = statusUpdate.status == .confirmed ? timestamp : nil
        
        return Address.Book.History.Transaction.Record(transactionHash: entry.transactionHash,
                                                       height: entry.height,
                                                       fee: entry.fee,
                                                       scriptHashes: [scriptHash],
                                                       firstSeenAt: timestamp,
                                                       lastUpdatedAt: timestamp,
                                                       status: statusUpdate.status,
                                                       confirmationHeight: confirmationHeight,
                                                       confirmedAt: confirmedAt)
    }
    
    func makeLedgerEntry() -> Storage.AccountSnapshot.TransactionLedger.Entry {
        Storage.AccountSnapshot.TransactionLedger.Entry(transactionHash: transactionHash.naturalOrder,
                                                        status: status.makeStorageStatus(),
                                                        confirmationHeight: confirmationHeight,
                                                        discoveredAt: firstSeenAt,
                                                        confirmedAt: confirmedAt,
                                                        label: nil,
                                                        memo: nil)
    }
}

private extension Address.Book.History.Transaction.Record.Status {
    static func resolve(forHeight height: Int,
                        previousStatus: Address.Book.History.Transaction.Record.Status?)
    -> (status: Address.Book.History.Transaction.Record.Status,
        confirmationHeight: UInt64?)
    {
        if height > 0 {
            return (.confirmed, UInt64(height))
        }
        
        guard let previousStatus else {
            return (.discovered, nil)
        }
        
        switch previousStatus {
        case .confirmed:
            return (.pending, nil)
        case .discovered:
            return (.pending, nil)
        case .pending, .failed:
            return (previousStatus, nil)
        }
    }
    
    func makeStorageStatus() -> Storage.AccountSnapshot.TransactionLedger.Entry.Status {
        switch self {
        case .discovered:
            return .discovered
        case .pending:
            return .pending
        case .confirmed:
            return .confirmed
        case .failed:
            return .failed
        }
    }
}
