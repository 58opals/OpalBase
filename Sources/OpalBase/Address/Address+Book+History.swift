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
}

extension Address.Book.History.Transaction.Record {
    mutating func resolveUpdate(from entry: Address.Book.History.Transaction.Entry,
                                scriptHash: String,
                                timestamp: Date) {
        height = entry.height
        fee = entry.fee
        lastUpdatedAt = timestamp
        scriptHashes.insert(scriptHash)
        
        let statusUpdate = Address.Book.History.Transaction.Status
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
    
    static func makeRecord(for entry: Address.Book.History.Transaction.Entry,
                           scriptHash: String,
                           timestamp: Date) -> Address.Book.History.Transaction.Record {
        let statusUpdate = Address.Book.History.Transaction.Status
            .resolve(forHeight: entry.height, previousStatus: nil)
        let confirmationHeight = statusUpdate.status == .confirmed
        ? (statusUpdate.confirmationHeight ?? UInt64(entry.height))
        : nil
        let confirmedAt = statusUpdate.status == .confirmed ? timestamp : nil
        let verificationStatus: Address.Book.History.Transaction.VerificationStatus = statusUpdate.status == .confirmed ? .pending : .unknown
        
        return Address.Book.History.Transaction.Record(transactionHash: entry.transactionHash,
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
}

extension Address.Book.History.Transaction.Status {
    static func resolve(forHeight height: Int,
                        previousStatus: Address.Book.History.Transaction.Status?)
    -> (status: Address.Book.History.Transaction.Status,
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
}

extension Address.Book.History.Transaction.Record {
    mutating func resetVerification(for status: Address.Book.History.Transaction.Status,
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
    
    mutating func updateVerification(status: Address.Book.History.Transaction.VerificationStatus,
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
