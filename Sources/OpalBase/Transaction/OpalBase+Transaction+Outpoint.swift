// OpalBase+Transaction+Outpoint.swift

import Foundation

extension _OpalBase.Transaction {
    public struct Outpoint: Sendable, Hashable, Codable {
        public let transactionHash: OpalBase.Transaction.Hash
        public let outputIndex: UInt32

        public init(
            transactionHash: OpalBase.Transaction.Hash,
            outputIndex: UInt32
        ) {
            self.transactionHash = transactionHash
            self.outputIndex = outputIndex
        }

        public init(_ input: OpalBase.Transaction.Input) {
            self.init(
                transactionHash: input.previousTransactionHash,
                outputIndex: input.previousTransactionOutputIndex
            )
        }

        public init(_ unspentOutput: OpalBase.Transaction.Output.Unspent) {
            self.init(
                transactionHash: unspentOutput.previousTransactionHash,
                outputIndex: unspentOutput.previousTransactionOutputIndex
            )
        }
    }
}
