// ClaimableUnspentOutpoint.swift

import Foundation

struct ClaimableUnspentOutpoint: Hashable {
    let transactionHash: OpalBase.Transaction.Hash
    let outputIndex: UInt32

    init(_ unspentOutput: OpalBase.Transaction.Output.Unspent) {
        self.transactionHash = unspentOutput.previousTransactionHash
        self.outputIndex = unspentOutput.previousTransactionOutputIndex
    }
}
