// TransactionModel+HistoryModel+RecordModel.swift

import Foundation

extension TransactionModel.HistoryModel {
    public struct RecordModel: Sendable, Hashable, Equatable {
        public struct ChainMetadata: Sendable, Hashable, Equatable {
            public var height: Int
            public var fee: UInt64?
            public var scriptHashes: Set<String>
            public var firstSeenAt: Date
            public var lastUpdatedAt: Date
        }
        
        public struct ConfirmationMetadata: Sendable, Hashable, Equatable {
            public var height: UInt64?
            public var confirmedAt: Date?
        }
        
        public struct VerificationMetadata: Sendable, Hashable, Equatable {
            public var status: StatusModel.Verification
            public var merkleProof: TransactionModel.MerkleProofModel?
            public var lastVerifiedHeight: UInt32?
            public var lastCheckedAt: Date?
            
            mutating func synchronize(with recordStatus: TransactionModel.HistoryModel.StatusModel,
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
        
        public let transactionHash: TransactionModel.HashModel
        
        public var chainMetadata: ChainMetadata
        public var confirmationMetadata: ConfirmationMetadata
        public var verificationMetadata: VerificationMetadata
        public var tokenDelta: TokenDeltaModel
        
        public var status: StatusModel
        
        public var isConfirmed: Bool { status == .confirmed }
        
        public init(transactionHash: TransactionModel.HashModel,
                    status: StatusModel,
                    chainMetadata: ChainMetadata,
                    confirmationMetadata: ConfirmationMetadata,
                    verificationMetadata: VerificationMetadata,
                                        tokenDelta: TokenDeltaModel = .init()) {
            self.transactionHash = transactionHash
            self.chainMetadata = chainMetadata
            self.confirmationMetadata = confirmationMetadata
            self.verificationMetadata = verificationMetadata
            self.tokenDelta = tokenDelta
            self.status = status
        }
    }
}

extension TransactionModel.HistoryModel.RecordModel {
    mutating func resolveUpdate(from entry: TransactionModel.HistoryModel.EntryModel,
                                scriptHash: String,
                                timestamp: Date) {
        applyEntryDetails(from: entry, scriptHash: scriptHash, timestamp: timestamp)
        
        let statusTransition = TransactionModel.HistoryModel.StatusModel
            .makeTransition(forHeight: entry.height, from: status)
        applyStatusTransition(statusTransition,
                              entryHeight: entry.height,
                              timestamp: timestamp)
    }
    
    static func makeRecord(for entry: TransactionModel.HistoryModel.EntryModel,
                           scriptHash: String,
                           timestamp: Date) -> TransactionModel.HistoryModel.RecordModel {
        let statusTransition = TransactionModel.HistoryModel.StatusModel
            .makeTransition(forHeight: entry.height, from: nil)
        let confirmationHeight = statusTransition
            .resolveConfirmationHeight(forHeight: entry.height)
        let confirmedAt = statusTransition.isConfirmed ? timestamp : nil
        let verificationStatus: TransactionModel.HistoryModel.StatusModel.Verification = statusTransition.isConfirmed ? .pending : .unknown
        let chainMetadata = TransactionModel.HistoryModel.RecordModel.ChainMetadata(height: entry.height,
                                                                     fee: entry.fee,
                                                                     scriptHashes: [scriptHash],
                                                                     firstSeenAt: timestamp,
                                                                     lastUpdatedAt: timestamp)
        let confirmationMetadata = TransactionModel.HistoryModel.RecordModel.ConfirmationMetadata(height: confirmationHeight,
                                                                                   confirmedAt: confirmedAt)
        let verificationMetadata = TransactionModel.HistoryModel.RecordModel.VerificationMetadata(status: verificationStatus,
                                                                                   merkleProof: nil,
                                                                                   lastVerifiedHeight: nil,
                                                                                   lastCheckedAt: nil)
        return TransactionModel.HistoryModel.RecordModel(transactionHash: entry.transactionHash,
                                          status: statusTransition.status,
                                          chainMetadata: chainMetadata,
                                          confirmationMetadata: confirmationMetadata,
                                          verificationMetadata: verificationMetadata,
                                                                                   tokenDelta: .init())
    }
    
    mutating func resetVerification(for status: TransactionModel.HistoryModel.StatusModel,
                                    timestamp: Date) {
        verificationMetadata.synchronize(with: status,
                                         timestamp: timestamp,
                                         shouldResetExistingVerification: true)
    }
    
    mutating func updateVerification(status: TransactionModel.HistoryModel.StatusModel.Verification,
                                     proof: TransactionModel.MerkleProofModel?,
                                     verifiedHeight: UInt32?,
                                     checkedAt: Date) {
        verificationMetadata.status = status
        verificationMetadata.merkleProof = proof
        verificationMetadata.lastVerifiedHeight = verifiedHeight
        verificationMetadata.lastCheckedAt = checkedAt
    }
    
    mutating func updateTokenDelta(_ tokenDelta: TokenDeltaModel) {
            self.tokenDelta = tokenDelta
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
    
    private mutating func applyEntryDetails(from entry: TransactionModel.HistoryModel.EntryModel,
                                            scriptHash: String,
                                            timestamp: Date) {
        chainMetadata.height = entry.height
        chainMetadata.fee = entry.fee
        chainMetadata.lastUpdatedAt = timestamp
        chainMetadata.scriptHashes.insert(scriptHash)
    }
    
    private mutating func applyStatusTransition(_ transition: TransactionModel.HistoryModel.StatusModel.TransitionModel,
                                                entryHeight: Int,
                                                timestamp: Date) {
        status = transition.status
        updateConfirmation(for: transition, entryHeight: entryHeight, timestamp: timestamp)
        updateVerification(afterStatusChange: transition.status, timestamp: timestamp)
    }
    
    private mutating func updateConfirmation(for transition: TransactionModel.HistoryModel.StatusModel.TransitionModel,
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
    
    private mutating func updateVerification(afterStatusChange status: TransactionModel.HistoryModel.StatusModel,
                                             timestamp: Date) {
        verificationMetadata.synchronize(with: status,
                                         timestamp: timestamp,
                                         shouldResetExistingVerification: false)
    }
}
