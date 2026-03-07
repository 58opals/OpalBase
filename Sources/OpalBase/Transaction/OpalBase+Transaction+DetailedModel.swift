// OpalBase+Transaction+DetailedModel.swift

import Foundation

extension _OpalBase.Transaction {
    /// A detailed representation of a transaction.
    ///
    /// - Parameters:
    ///   - transaction: The full transaction.
    ///   - blockHash: The block hash if confirmed.
    ///   - blockTime: The block time if confirmed.
    ///   - confirmations: The number of confirmations.
    ///   - hash: The transaction hash.
    ///   - rawTransactionData: The raw transaction payload as returned by the network.
    ///   - size: The transaction size in bytes.
    ///   - time: The transaction time if available.
    public struct DetailedModel {
        public let transaction: OpalBase.Transaction
        
        public let blockHash: Data?
        public let blockTime: UInt32?
        public let confirmations: UInt32?
        public let hash: OpalBase.Transaction.HashModel
        public let rawTransactionData: Data
        public let size: UInt32
        public let time: UInt32?
    }
}

extension _OpalBase.Transaction.DetailedModel: Sendable {}
