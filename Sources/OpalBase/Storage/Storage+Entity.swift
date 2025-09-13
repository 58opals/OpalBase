// Storage+Entity.swift

import Foundation

extension Storage {
    public enum Entity {}
}

#if canImport(SwiftData)
import SwiftData

extension Storage.Entity {
    @Model
    public final class HeaderModel {
        @Attribute(.unique) public var height: UInt32
        public var version: Int32
        public var previousBlockHash: Data
        public var merkleRoot: Data
        public var time: UInt32
        public var bits: UInt32
        public var nonce: UInt32
        public var hash: Data
        
        public init(height: UInt32,
                    version: Int32,
                    previousBlockHash: Data,
                    merkleRoot: Data,
                    time: UInt32,
                    bits: UInt32,
                    nonce: UInt32,
                    hash: Data)
        {
            self.height = height
            self.version = version
            self.previousBlockHash = previousBlockHash
            self.merkleRoot = merkleRoot
            self.time = time
            self.bits = bits
            self.nonce = nonce
            self.hash = hash
        }
    }
    
    @Model
    public final class UTXOModel {
        @Attribute(.unique) public var key: String // "\(transactionHash.hex):\(outputIndex)"
        public var transactionHash: Data
        public var outputIndex: UInt32
        public var value: UInt64
        public var lockingScript: Data
        public var accountIndex: UInt32 // BIP44 account index
        
        public init(transactionHash: Transaction.Hash, outputIndex: UInt32, value: UInt64, lockingScript: Data, accountIndex: UInt32) {
            self.transactionHash = transactionHash.naturalOrder
            self.outputIndex = outputIndex
            self.value = value
            self.lockingScript = lockingScript
            self.accountIndex = accountIndex
            self.key = UTXOModel.makeKey(transactionHash: transactionHash, outputIndex: outputIndex)
        }
        
        public static func makeKey(transactionHash: Transaction.Hash, outputIndex: UInt32) -> String {
            transactionHash.naturalOrder.map { String(format: "%02x", $0) }.joined() + ":" + String(outputIndex)
        }
    }
    
    @Model
    public final class TransactionModel {
        @Attribute(.unique) public var hash: Data
        public var raw: Data
        public var height: UInt32?
        public var time: UInt32?
        public var fee: UInt64?
        public var isPending: Bool
        public var accountIndex: UInt32?
        
        public init(hash: Data, raw: Data, height: UInt32?, time: UInt32?, fee: UInt64?, isPending: Bool, accountIndex: UInt32?) {
            self.hash = hash
            self.raw = raw
            self.height = height
            self.time = time
            self.fee = fee
            self.isPending = isPending
            self.accountIndex = accountIndex
        }
    }
    
    @Model
    public final class AccountModel {
        @Attribute(.unique) public var id: String // "\(purpose)-\(coinType)-\(index)"
        public var purpose: UInt32 // 44 for BIP44
        public var coinType: UInt32 // 145 for BCH
        public var index: UInt32 // unhardened account index
        public var label: String?
        
        public init(purpose: UInt32, coinType: UInt32, index: UInt32, label: String? = nil) {
            self.purpose = purpose
            self.coinType = coinType
            self.index = index
            self.label = label
            self.id = "\(purpose)-\(coinType)-\(index)"
        }
    }
    
    @Model
    public final class FeeModel {
        public enum Tier: String, Codable, CaseIterable { case slow, normal, fast }
        @Attribute(.unique) public var tier: String
        public var satsPerByte: UInt64
        public var timestamp: Date
        
        public init(tier: Tier, satsPerByte: UInt64, timestamp: Date = .now) {
            self.tier = tier.rawValue
            self.satsPerByte = satsPerByte
            self.timestamp = timestamp
        }
    }
    
    @Model
    public final class ServerHealthModel {
        @Attribute(.unique) public var url: String
        public var latencyMs: Double?
        public var status: String // healthy | degraded | unhealthy
        public var failures: Int
        public var quarantineUntil: Date?
        public var lastOK: Date?
        
        public init(url: String,
                    latencyMs: Double?,
                    status: String,
                    failures: Int,
                    quarantineUntil: Date?,
                    lastOK: Date?)
        {
            self.url = url
            self.latencyMs = latencyMs
            self.status = status
            self.failures = failures
            self.quarantineUntil = quarantineUntil
            self.lastOK = lastOK
        }
    }
    
    @Model
    public final class SubscriptionModel {
        @Attribute(.unique) public var address: String
        public var isActive: Bool
        public var lastStatus: String?
        public var lastUpdated: Date?
        
        public init(address: String, isActive: Bool, lastStatus: String?, lastUpdated: Date? = .now) {
            self.address = address
            self.isActive = isActive
            self.lastStatus = lastStatus
            self.lastUpdated = lastUpdated
        }
    }
}
#endif
