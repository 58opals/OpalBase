// OpalBase+ReusablePaymentAddress+ConfirmedTransactionReference.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    /// A confirmed transaction reference returned by an RPA-capable backend.
    ///
    /// This is a candidate reference. It is not a Cash Code payment match.
    public struct ConfirmedTransactionReference:
        Sendable,
        Hashable
    {
        public let transactionHash: OpalBase.Transaction.Hash
        public let blockHeight: UInt

        public init(
            transactionHash: OpalBase.Transaction.Hash,
            blockHeight: UInt
        ) {
            self.transactionHash = transactionHash
            self.blockHeight = blockHeight
        }
    }
}
