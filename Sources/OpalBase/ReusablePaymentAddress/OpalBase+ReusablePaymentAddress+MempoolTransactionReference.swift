// OpalBase+ReusablePaymentAddress+MempoolTransactionReference.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    /// An unconfirmed transaction reference returned by an RPA-capable
    /// backend.
    ///
    /// This is a candidate reference. It is not a Cash Code payment match.
    public struct MempoolTransactionReference:
        Sendable,
        Hashable
    {
        public let transactionHash: OpalBase.Transaction.Hash
        public let fee: UInt64
        public let hasUnconfirmedParent: Bool

        public init(
            transactionHash: OpalBase.Transaction.Hash,
            fee: UInt64,
            hasUnconfirmedParent: Bool
        ) {
            self.transactionHash = transactionHash
            self.fee = fee
            self.hasUnconfirmedParent = hasUnconfirmedParent
        }
    }
}
