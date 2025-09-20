// Storage+Row.swift

import Foundation

extension Storage {
    public enum Row {
        public struct Header: Sendable, Codable, Hashable {
            public let height: UInt32,
                       version: Int32,
                       previousBlockHash: Data,
                       merkleRoot: Data,
                       time: UInt32,
                       bits: UInt32,
                       nonce: UInt32,
                       hash: Data
        }
        
        public struct UTXO: Sendable, Codable, Hashable {
            public let key: String,
                       txHash: Data,
                       index: UInt32,
                       value: UInt64,
                       lockingScript: Data,
                       accountIndex: UInt32
        }
        
        public struct Fee: Sendable, Codable, Hashable {
            public let tier: Storage.Entity.FeeModel.Tier,
                       satsPerByte: UInt64,
                       timestamp: Date
        }
        
        public struct Transaction: Sendable, Codable, Hashable {
            public let hash: Data,
                       raw: Data,
                       height: UInt32?,
                       time: UInt32?,
                       fee: UInt64?,
                       isPending: Bool,
                       accountIndex: UInt32?
        }
        
        public struct Subscription: Sendable, Codable, Hashable {
            public let address: String,
                       isActive: Bool,
                       lastStatus: String?,
                       lastUpdated: Date?
        }
        
        public struct ServerHealth: Sendable, Codable, Hashable {
            public let url: String,
                       latencyMs: Double?,
                       status: String,
                       failures: Int,
                       quarantineUntil: Date?,
                       lastOK: Date?
        }
    }
}

// Mapping helpers kept inside the storage module
extension Storage.Entity.HeaderModel {
    var row: Storage.Row.Header { .init(height: height,
                                        version: version,
                                        previousBlockHash: previousBlockHash,
                                        merkleRoot: merkleRoot,
                                        time: time,
                                        bits: bits,
                                        nonce: nonce,
                                        hash: hash) }
}
extension Storage.Entity.UTXOModel {
    var row: Storage.Row.UTXO { .init(key: key,
                                      txHash: transactionHash,
                                      index: outputIndex,
                                      value: value,
                                      lockingScript: lockingScript,
                                      accountIndex: accountIndex) }
}
extension Storage.Entity.FeeModel {
    var row: Storage.Row.Fee {
        guard let parsedTier = Storage.Entity.FeeModel.Tier(rawValue: tier) else {
            preconditionFailure("Unsupported fee tier: \(tier)")
        }
        return .init(tier: parsedTier, satsPerByte: satsPerByte, timestamp: timestamp)
    }
}
extension Storage.Entity.TransactionModel {
    var row: Storage.Row.Transaction { .init(hash: hash,
                                             raw: raw,
                                             height: height,
                                             time: time,
                                             fee: fee,
                                             isPending: isPending,
                                             accountIndex: accountIndex) }
}
extension Storage.Entity.SubscriptionModel {
    var row: Storage.Row.Subscription { .init(address: address,
                                              isActive: isActive,
                                              lastStatus: lastStatus,
                                              lastUpdated: lastUpdated) }
}
extension Storage.Entity.ServerHealthModel {
    var row: Storage.Row.ServerHealth { .init(url: url,
                                              latencyMs: latencyMs,
                                              status: status,
                                              failures: failures,
                                              quarantineUntil: quarantineUntil,
                                              lastOK: lastOK) }
}
