// OpalBase+ReusablePaymentAddress+ReceiveCandidate.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct ReceiveCandidate: Sendable, Hashable {
        public let transactionHash: OpalBase.Transaction.Hash
        public let blockHeight: Int
        public let outputIndex: UInt32
        public let value: UInt64
        public let lockingScript: Data
        public let inputMetadata: [TransactionInputMetadata]

        public init(
            transactionHash: OpalBase.Transaction.Hash,
            blockHeight: Int,
            outputIndex: UInt32,
            value: UInt64,
            lockingScript: Data,
            inputMetadata: [TransactionInputMetadata]
        ) throws {
            guard blockHeight >= 0 else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidBlockHeight(blockHeight)
            }
            self.transactionHash = transactionHash
            self.blockHeight = blockHeight
            self.outputIndex = outputIndex
            self.value = value
            self.lockingScript = Data(lockingScript)
            self.inputMetadata = inputMetadata
        }

        public var outpoint: OpalBase.Transaction.Outpoint {
            OpalBase.Transaction.Outpoint(
                transactionHash: transactionHash,
                outputIndex: outputIndex
            )
        }
    }
}
