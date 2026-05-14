// TransactionHistoryRecordValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("OpalBase.Transaction.History.Record", .tags(.unit, .wallet))
struct TransactionHistoryRecordValidator {
    @Test("network history reactivates previously failed unconfirmed transactions")
    func networkHistoryReactivatesPreviouslyFailedUnconfirmedTransactions() {
        let transactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x20, count: 32))
        let scriptHash = String(repeating: "b", count: 64)
        var record = OpalBase.Transaction.History.Record(
            transactionHash: transactionHash,
            status: .failed,
            chainMetadata: .init(
                height: 0,
                fee: nil,
                scriptHashes: [scriptHash],
                firstSeenAt: Date(timeIntervalSince1970: 1),
                lastUpdatedAt: Date(timeIntervalSince1970: 1)
            ),
            confirmationMetadata: .init(height: nil, confirmedAt: nil),
            verificationMetadata: .init(
                status: .unknown,
                merkleProof: nil,
                lastVerifiedHeight: nil,
                lastCheckedAt: nil
            )
        )
        
        record.resolveUpdate(
            from: .init(transactionHash: transactionHash, height: -1, fee: nil),
            scriptHash: scriptHash,
            timestamp: Date(timeIntervalSince1970: 2)
        )
        
        #expect(record.status == .pending)
        #expect(record.verificationMetadata.status == .pending)
        #expect(record.confirmationMetadata.height == nil)
    }
    
    @Test("confirmation height changes reset merkle verification")
    func validateConfirmationHeightChangesResetMerkleVerification() {
        let transactionHash = OpalBase.Transaction.Hash(naturalOrder: Data(repeating: 0x21, count: 32))
        let scriptHash = String(repeating: "a", count: 64)
        var record = OpalBase.Transaction.History.Record.makeRecord(
            for: .init(transactionHash: transactionHash, height: 10, fee: nil),
            scriptHash: scriptHash,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let proof = OpalBase.Transaction.MerkleProof(
            blockHeight: 10,
            position: 0,
            branch: [Data(repeating: 0x31, count: 32)]
        )
        record.updateVerification(
            status: .verified,
            proof: proof,
            verifiedHeight: 10,
            checkedAt: Date(timeIntervalSince1970: 2)
        )

        record.resolveUpdate(
            from: .init(transactionHash: transactionHash, height: 11, fee: nil),
            scriptHash: scriptHash,
            timestamp: Date(timeIntervalSince1970: 3)
        )

        #expect(record.confirmationMetadata.height == 11)
        #expect(record.verificationMetadata.status == .pending)
        #expect(record.verificationMetadata.merkleProof == nil)
        #expect(record.verificationMetadata.lastVerifiedHeight == nil)
    }
}
