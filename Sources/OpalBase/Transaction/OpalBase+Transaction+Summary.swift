// OpalBase+Transaction+Summary.swift

import Foundation

extension _OpalBase.Transaction {
    /// A simplified representation of a transaction.
    ///
    /// - Parameters:
    ///   - transactionHash: The transaction hash.
    ///   - height: The block height if confirmed.
    ///   - fee: The transaction fee.
    public struct Summary {
        public let transactionHash: OpalBase.Transaction.Hash
        public let height: UInt32?
        public let fee: UInt64?
    }
}

extension _OpalBase.Transaction.Summary: Sendable {}

extension _OpalBase.Transaction.Summary: CustomStringConvertible {
    public var description: String {
        var description = "Simplified OpalBase.Transaction: \(transactionHash.naturalOrder.hexadecimalString)"
        
        if let height {
            description += " at \(height)"
        } else {
            description += " (unconfirmed)"
        }
        
        if let fee {
            description += " with \(fee) fee"
        }
        
        return description
    }
}
