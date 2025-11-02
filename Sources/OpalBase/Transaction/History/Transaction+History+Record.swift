// Transaction+History+Record.swift

import Foundation

extension Transaction.History {
    public struct Record: Sendable, Hashable, Equatable {
        public struct ChainMetadata: Sendable, Hashable, Equatable {
            var height: Int
            var fee: UInt?
            var scriptHashes: Set<String>
            var firstSeenAt: Date
            var lastUpdatedAt: Date
        }
        
        public struct ConfirmationMetadata: Sendable, Hashable, Equatable {
            var height: UInt64?
            var confirmedAt: Date?
        }
        
        public struct VerificationMetadata: Sendable, Hashable, Equatable {
            var status: Status.Verification
            var merkleProof: Transaction.MerkleProof?
            var lastVerifiedHeight: UInt32?
            var lastCheckedAt: Date?
        }
        
        public let transactionHash: Transaction.Hash
        
        public var chainMetadata: ChainMetadata
        public var confirmationMetadata: ConfirmationMetadata
        public var verificationMetadata: VerificationMetadata
        
        public var height: Int
        public var fee: UInt?
        public var scriptHashes: Set<String>
        public let firstSeenAt: Date
        public var lastUpdatedAt: Date
        
        public var status: Status
        public var confirmationHeight: UInt64?
        public var confirmedAt: Date?
        
        public var verificationStatus: Status.Verification
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
                    verificationStatus: Status.Verification,
                    merkleProof: Transaction.MerkleProof?,
                    lastVerifiedHeight: UInt32?,
                    lastCheckedAt: Date?) {
            self.transactionHash = transactionHash
            self.chainMetadata = .init(height: height,
                                       fee: fee,
                                       scriptHashes: scriptHashes,
                                       firstSeenAt: firstSeenAt,
                                       lastUpdatedAt: lastUpdatedAt)
            self.confirmationMetadata = .init(height: confirmationHeight,
                                              confirmedAt: confirmedAt)
            self.verificationMetadata = .init(status: verificationStatus,
                                              merkleProof: merkleProof,
                                              lastVerifiedHeight: lastVerifiedHeight,
                                              lastCheckedAt: lastCheckedAt)
            
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

extension Transaction.History.Record {
    mutating func resolveUpdate(from entry: Transaction.History.Entry,
                                scriptHash: String,
                                timestamp: Date) {
        applyEntryDetails(from: entry, scriptHash: scriptHash, timestamp: timestamp)
        
        let statusTransition = Transaction.History.Status
            .makeTransition(forHeight: entry.height, from: status)
        applyStatusTransition(statusTransition,
                              entryHeight: entry.height,
                              timestamp: timestamp)
    }
    
    static func makeRecord(for entry: Transaction.History.Entry,
                           scriptHash: String,
                           timestamp: Date) -> Transaction.History.Record {
        let statusTransition = Transaction.History.Status
            .makeTransition(forHeight: entry.height, from: nil)
        let confirmationHeight = statusTransition
            .resolveConfirmationHeight(forHeight: entry.height)
        let confirmedAt = statusTransition.isConfirmed ? timestamp : nil
        let verificationStatus: Transaction.History.Status.Verification = statusTransition.isConfirmed ? .pending : .unknown
        return Transaction.History.Record(transactionHash: entry.transactionHash,
                                          height: entry.height,
                                          fee: entry.fee,
                                          scriptHashes: [scriptHash],
                                          firstSeenAt: timestamp,
                                          lastUpdatedAt: timestamp,
                                          status: statusTransition.status,
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
    
    mutating func updateVerification(status: Transaction.History.Status.Verification,
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
    
    private mutating func applyEntryDetails(from entry: Transaction.History.Entry,
                                            scriptHash: String,
                                            timestamp: Date) {
        height = entry.height
        fee = entry.fee
        lastUpdatedAt = timestamp
        scriptHashes.insert(scriptHash)
    }
    
    private mutating func applyStatusTransition(_ transition: Transaction.History.Status.Transition,
                                                entryHeight: Int,
                                                timestamp: Date) {
        status = transition.status
        updateConfirmation(for: transition, entryHeight: entryHeight, timestamp: timestamp)
        updateVerification(afterStatusChange: transition.status, timestamp: timestamp)
    }
    
    private mutating func updateConfirmation(for transition: Transaction.History.Status.Transition,
                                             entryHeight: Int,
                                             timestamp: Date) {
        if let newHeight = transition.resolveConfirmationHeight(forHeight: entryHeight) {
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
    
    private mutating func updateVerification(afterStatusChange status: Transaction.History.Status,
                                             timestamp: Date) {
        switch status {
        case .confirmed:
            if verificationStatus == .unknown {
                verificationStatus = .pending
            }
        case .pending:
            verificationStatus = .pending
        case .discovered, .failed:
            verificationStatus = .unknown
        }
        
        if status != .confirmed {
            merkleProof = nil
            lastVerifiedHeight = nil
        }
        lastCheckedAt = timestamp
    }
}
