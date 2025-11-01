// Address+Book~Transaction.swift

import Foundation

extension Address.Book {
    public func listTransactionHistory() -> [Transaction.History.Record] {
        transactionLog.listRecords()
    }
}

extension Address.Book {
    func updateTransactionHistory(for scriptHash: String,
                                  entries: [Transaction.History.Entry],
                                  timestamp: Date = .now) -> Transaction.History.ChangeSet {
        transactionLog.updateHistory(for: scriptHash,
                                     entries: entries,
                                     timestamp: timestamp)
    }
    
    func updateTransactionVerification(for transactionHash: Transaction.Hash,
                                       status: Transaction.History.VerificationStatus,
                                       proof: Transaction.MerkleProof?,
                                       verifiedHeight: UInt32?,
                                       timestamp: Date = .now) -> Transaction.History.Record? {
        transactionLog.updateVerification(for: transactionHash,
                                          status: status,
                                          proof: proof,
                                          verifiedHeight: verifiedHeight,
                                          timestamp: timestamp)
    }
    
    func invalidateConfirmations(startingAt height: UInt32,
                                 timestamp: Date = .now) -> [Transaction.History.Record] {
        transactionLog.invalidateConfirmations(startingAt: height,
                                               timestamp: timestamp)
    }
}
