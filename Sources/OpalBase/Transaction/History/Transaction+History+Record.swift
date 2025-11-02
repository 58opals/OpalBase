// Transaction+History+Record.swift

import Foundation

extension Transaction.History {
    public struct Record: Sendable, Hashable, Equatable {
        public struct ChainMetadata: Sendable, Hashable, Equatable {
            public var height: Int
            public var fee: UInt?
            public var scriptHashes: Set<String>
            public var firstSeenAt: Date
            public var lastUpdatedAt: Date
        }
        
        public struct ConfirmationMetadata: Sendable, Hashable, Equatable {
            public var height: UInt64?
            public var confirmedAt: Date?
        }
        
        public struct VerificationMetadata: Sendable, Hashable, Equatable {
            public var status: Status.Verification
            public var merkleProof: Transaction.MerkleProof?
            public var lastVerifiedHeight: UInt32?
            public var lastCheckedAt: Date?
            
            mutating func synchronize(with recordStatus: Transaction.History.Status,
                                      timestamp: Date,
                                      shouldResetExistingVerification: Bool) {
                switch recordStatus {
                case .confirmed:
                    if shouldResetExistingVerification {
                        status = .pending
                    } else if status == .unknown {
                        status = .pending
                    }
                case .pending:
                    status = .pending
                case .discovered, .failed:
                    status = .unknown
                }
                
                if shouldResetExistingVerification || recordStatus != .confirmed {
                    merkleProof = nil
                    lastVerifiedHeight = nil
                }
                lastCheckedAt = timestamp
            }
        }
        
        public let transactionHash: Transaction.Hash
        
        public var chainMetadata: ChainMetadata
        public var confirmationMetadata: ConfirmationMetadata
        public var verificationMetadata: VerificationMetadata
        
        public var status: Status
        
        public var isConfirmed: Bool { status == .confirmed }
        
        public init(transactionHash: Transaction.Hash,
                    status: Status,
                    chainMetadata: ChainMetadata,
                    confirmationMetadata: ConfirmationMetadata,
                    verificationMetadata: VerificationMetadata) {
            self.transactionHash = transactionHash
            self.chainMetadata = chainMetadata
            self.confirmationMetadata = confirmationMetadata
            self.verificationMetadata = verificationMetadata
            self.status = status
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
        let chainMetadata = Transaction.History.Record.ChainMetadata(height: entry.height,
                                                                     fee: entry.fee,
                                                                     scriptHashes: [scriptHash],
                                                                     firstSeenAt: timestamp,
                                                                     lastUpdatedAt: timestamp)
        let confirmationMetadata = Transaction.History.Record.ConfirmationMetadata(height: confirmationHeight,
                                                                                   confirmedAt: confirmedAt)
        let verificationMetadata = Transaction.History.Record.VerificationMetadata(status: verificationStatus,
                                                                                   merkleProof: nil,
                                                                                   lastVerifiedHeight: nil,
                                                                                   lastCheckedAt: nil)
        return Transaction.History.Record(transactionHash: entry.transactionHash,
                                          status: statusTransition.status,
                                          chainMetadata: chainMetadata,
                                          confirmationMetadata: confirmationMetadata,
                                          verificationMetadata: verificationMetadata)
    }
    
    mutating func resetVerification(for status: Transaction.History.Status,
                                    timestamp: Date) {
        verificationMetadata.synchronize(with: status,
                                         timestamp: timestamp,
                                         shouldResetExistingVerification: true)
    }
    
    mutating func updateVerification(status: Transaction.History.Status.Verification,
                                     proof: Transaction.MerkleProof?,
                                     verifiedHeight: UInt32?,
                                     checkedAt: Date) {
        verificationMetadata.status = status
        verificationMetadata.merkleProof = proof
        verificationMetadata.lastVerifiedHeight = verifiedHeight
        verificationMetadata.lastCheckedAt = checkedAt
    }
    
    mutating func markAsPendingAfterReorganization(timestamp: Date) {
        status = .pending
        chainMetadata.height = -1
        confirmationMetadata.height = nil
        confirmationMetadata.confirmedAt = nil
        verificationMetadata.synchronize(with: .pending,
                                         timestamp: timestamp,
                                         shouldResetExistingVerification: true)
    }
    
    private mutating func applyEntryDetails(from entry: Transaction.History.Entry,
                                            scriptHash: String,
                                            timestamp: Date) {
        chainMetadata.height = entry.height
        chainMetadata.fee = entry.fee
        chainMetadata.lastUpdatedAt = timestamp
        chainMetadata.scriptHashes.insert(scriptHash)
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
            if let existingHeight = confirmationMetadata.height, existingHeight != newHeight {
                confirmationMetadata.confirmedAt = timestamp
            } else if confirmationMetadata.confirmedAt == nil {
                confirmationMetadata.confirmedAt = timestamp
            }
            confirmationMetadata.height = newHeight
        } else {
            confirmationMetadata.height = nil
            confirmationMetadata.confirmedAt = nil
        }
    }
    
    private mutating func updateVerification(afterStatusChange status: Transaction.History.Status,
                                             timestamp: Date) {
        verificationMetadata.synchronize(with: status,
                                         timestamp: timestamp,
                                         shouldResetExistingVerification: false)
    }
}
