// Transaction+History.swift

import Foundation

extension Transaction { public enum History {} }

extension Transaction.History {
    public enum Status: String, Sendable, Hashable, Codable {
        case discovered
        case pending
        case confirmed
        case failed
    }
    
    public enum VerificationStatus: String, Sendable, Hashable, Codable {
        case unknown
        case pending
        case verified
        case conflicting
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
        
        public var verificationStatus: VerificationStatus
        public var merkleProof: Transaction.MerkleProof?
        public var lastVerifiedHeight: UInt32?
        public var lastCheckedAt: Date?
        
        public var isConfirmed: Bool { status == .confirmed }
        
        public init(transactionHash: Transaction.Hash,
                    height: Int,
                    fee: UInt?,
                    scriptHashes: Set<String>,
                    firstSeenAt: Date,
                    lastUpdatedAt: Date,
                    status: Status,
                    confirmationHeight: UInt64?,
                    confirmedAt: Date?,
                    verificationStatus: VerificationStatus,
                    merkleProof: Transaction.MerkleProof?,
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
    
    public struct ChangeSet: Sendable {
        public var inserted: [Record]
        public var updated: [Record]
        public var removed: [Transaction.Hash]
        
        public init(inserted: [Record] = .init(),
                    updated: [Record] = .init(),
                    removed: [Transaction.Hash] = .init()) {
            self.inserted = inserted
            self.updated = updated
            self.removed = removed
        }
        
        public var isEmpty: Bool { inserted.isEmpty && updated.isEmpty && removed.isEmpty }
    }
}

extension Transaction.History.Status {
    static func resolve(forHeight height: Int,
                        previousStatus: Transaction.History.Status?)
    -> (status: Transaction.History.Status, confirmationHeight: UInt64?)
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
}

extension Transaction.History.Record {
    mutating func resolveUpdate(from entry: Transaction.History.Entry,
                                scriptHash: String,
                                timestamp: Date) {
        height = entry.height
        fee = entry.fee
        lastUpdatedAt = timestamp
        scriptHashes.insert(scriptHash)
        
        let statusUpdate = Transaction.History.Status
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
        
        switch statusUpdate.status {
        case .confirmed:
            if verificationStatus == .unknown {
                verificationStatus = .pending
            }
        case .pending:
            verificationStatus = .pending
        case .discovered, .failed:
            verificationStatus = .unknown
        }
        
        if statusUpdate.status != .confirmed {
            merkleProof = nil
            lastVerifiedHeight = nil
        }
        lastCheckedAt = timestamp
    }
    
    static func makeRecord(for entry: Transaction.History.Entry,
                           scriptHash: String,
                           timestamp: Date) -> Transaction.History.Record {
        let statusUpdate = Transaction.History.Status
            .resolve(forHeight: entry.height, previousStatus: nil)
        let confirmationHeight = statusUpdate.status == .confirmed
        ? (statusUpdate.confirmationHeight ?? UInt64(entry.height))
        : nil
        let confirmedAt = statusUpdate.status == .confirmed ? timestamp : nil
        let verificationStatus: Transaction.History.VerificationStatus = statusUpdate.status == .confirmed ? .pending : .unknown
        return Transaction.History.Record(transactionHash: entry.transactionHash,
                                          height: entry.height,
                                          fee: entry.fee,
                                          scriptHashes: [scriptHash],
                                          firstSeenAt: timestamp,
                                          lastUpdatedAt: timestamp,
                                          status: statusUpdate.status,
                                          confirmationHeight: confirmationHeight,
                                          confirmedAt: confirmedAt,
                                          verificationStatus: verificationStatus,
                                          merkleProof: nil,
                                          lastVerifiedHeight: nil,
                                          lastCheckedAt: nil)
    }
    
    mutating func resetVerification(for status: Transaction.History.Status,
                                    timestamp: Date) {
        switch status {
        case .confirmed, .pending:
            verificationStatus = .pending
        case .discovered, .failed:
            verificationStatus = .unknown
        }
        merkleProof = nil
        lastVerifiedHeight = nil
        lastCheckedAt = timestamp
    }
    
    mutating func updateVerification(status: Transaction.History.VerificationStatus,
                                     proof: Transaction.MerkleProof?,
                                     verifiedHeight: UInt32?,
                                     checkedAt: Date) {
        verificationStatus = status
        merkleProof = proof
        lastVerifiedHeight = verifiedHeight
        lastCheckedAt = checkedAt
    }
    
    mutating func markAsPendingAfterReorganization(timestamp: Date) {
        status = .pending
        height = -1
        confirmationHeight = nil
        confirmedAt = nil
        verificationStatus = .pending
        merkleProof = nil
        lastVerifiedHeight = nil
        lastCheckedAt = timestamp
    }
}

extension Transaction.History.ChangeSet {
    mutating func applyVerificationUpdates(_ records: [Transaction.History.Record]) {
        guard !records.isEmpty else { return }
        for record in records {
            if let index = inserted.firstIndex(where: { $0.transactionHash == record.transactionHash }) {
                inserted[index] = record
            } else if let index = updated.firstIndex(where: { $0.transactionHash == record.transactionHash }) {
                updated[index] = record
            } else {
                updated.append(record)
            }
        }
    }
}
