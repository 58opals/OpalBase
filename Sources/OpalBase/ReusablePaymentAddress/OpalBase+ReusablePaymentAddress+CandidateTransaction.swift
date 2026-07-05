// OpalBase+ReusablePaymentAddress+CandidateTransaction.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct CandidateTransaction: Sendable, Hashable {
        public let transactionHash: OpalBase.Transaction.Hash
        public let blockHeight: Int
        public let rawTransactionData: Data
        public let inputMetadata: [TransactionInputMetadata]

        public init(
            transactionHash: OpalBase.Transaction.Hash,
            blockHeight: Int,
            rawTransactionData: Data,
            inputMetadata: [TransactionInputMetadata]
        ) throws {
            guard blockHeight >= 0 else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidBlockHeight(blockHeight)
            }
            self.transactionHash = transactionHash
            self.blockHeight = blockHeight
            self.rawTransactionData = Data(rawTransactionData)
            self.inputMetadata = inputMetadata
        }
    }
}
