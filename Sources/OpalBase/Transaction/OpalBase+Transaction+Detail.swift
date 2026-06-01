// OpalBase+Transaction+Detail.swift

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
    public struct Detail {
        public let transaction: OpalBase.Transaction
        
        public let blockHash: Data?
        public let blockTime: UInt32?
        public let confirmations: UInt32?
        public let hash: OpalBase.Transaction.Hash
        public let rawTransactionData: Data
        public let size: UInt32
        public let time: UInt32?

        init(
            transaction: OpalBase.Transaction,
            blockHash: Data?,
            blockTime: UInt32?,
            confirmations: UInt32?,
            hash: OpalBase.Transaction.Hash,
            rawTransactionData: Data,
            size: UInt32,
            time: UInt32?
        ) {
            self.transaction = transaction
            self.blockHash = blockHash.map { Data($0) }
            self.blockTime = blockTime
            self.confirmations = confirmations
            self.hash = hash
            self.rawTransactionData = Data(rawTransactionData)
            self.size = size
            self.time = time
        }
    }
}

extension _OpalBase.Transaction.Detail: Sendable {}
