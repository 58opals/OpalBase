// Storage+Repository.swift

import Foundation

public extension Storage {
    enum Repository {}
}

extension Storage.Repository {
    public actor TTLCache<Key: Hashable, Value> {
        private struct Item { let value: Value; let expiry: Date }
        private var items: [Key: Item] = [:]
        private let defaultTTL: TimeInterval
        
        public init(defaultTTL: TimeInterval) {
            self.defaultTTL = defaultTTL
        }
        
        public func get(_ key: Key) -> Value? {
            guard let item = items[key] else { return nil }
            if item.expiry > Date() { return item.value }
            items[key] = nil
            return nil
        }
        
        public func set(_ key: Key, _ value: Value, ttl: TimeInterval? = nil) {
            let exp = Date().addingTimeInterval(ttl ?? defaultTTL)
            items[key] = .init(value: value, expiry: exp)
        }
        
        public func invalidate(_ key: Key) { items[key] = nil }
        
        public func clear() { items.removeAll() }
    }
}

#if canImport(SwiftData)
import SwiftData

// Headers
public extension Storage.Repository {
    actor Headers {
        private let container: ModelContainer
        private let tipCache = TTLCache<String, Storage.Entity.Header>(defaultTTL: 600)
        
        public init(container: ModelContainer) { self.container = container }
        
        public func tip() async throws -> Storage.Entity.Header? {
            if let cached = await tipCache.get("tip") { return cached }
            return try Storage.Facade.withContext(container) { ctx in
                var desc = FetchDescriptor<Storage.Entity.Header>(predicate: nil,
                                                                  sortBy: [SortDescriptor(\.height, order: .reverse)])
                desc.fetchLimit = 1
                let found = try ctx.fetch(desc).first
                if let h = found { Task { await self.tipCache.set("tip", h) } }
                return found
            }
        }
        
        public func byHeight(_ height: UInt32) throws -> Storage.Entity.Header? {
            try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Header> { $0.height == height }
                let d = FetchDescriptor<Storage.Entity.Header>(predicate: p, sortBy: [])
                return try ctx.fetch(d).first
            }
        }
        
        public func upsertRange(_ entries: [(height: UInt32, header: Block.Header, hash: Data)]) async throws {
            try Storage.Facade.withContext(container) { ctx in
                for e in entries {
                    let p = #Predicate<Storage.Entity.Header> { $0.height == e.height }
                    if let existing = try ctx.fetch(FetchDescriptor(predicate: p)).first {
                        existing.version = e.header.version
                        existing.previousBlockHash = e.header.previousBlockHash
                        existing.merkleRoot = e.header.merkleRoot
                        existing.time = e.header.time
                        existing.bits = e.header.bits
                        existing.nonce = e.header.nonce
                        existing.hash = e.hash
                        ctx.insert(existing)
                    } else {
                        let m = Storage.Entity.Header(height: e.height,
                                                      version: e.header.version,
                                                      previousBlockHash: e.header.previousBlockHash,
                                                      merkleRoot: e.header.merkleRoot,
                                                      time: e.header.time,
                                                      bits: e.header.bits,
                                                      nonce: e.header.nonce,
                                                      hash: e.hash)
                        ctx.insert(m)
                    }
                }
            }
            await tipCache.invalidate("tip")
        }
        
        public func prune(below height: UInt32) async throws {
            try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Header> { $0.height < height }
                try ctx.delete(model: Storage.Entity.Header.self, where: p)
            }
            await tipCache.invalidate("tip")
        }
    }
}

// UTXOs
public extension Storage.Repository {
    actor UTXOs {
        private let container: ModelContainer
        private let cache = TTLCache<String, [Storage.Entity.UTXO]>(defaultTTL: 300)
        
        public init(container: ModelContainer) { self.container = container }
        
        public func forAccount(_ index: UInt32) async throws -> [Storage.Entity.UTXO] {
            let key = "a:\(index)"
            if let cached = await cache.get(key) { return cached }
            let result = try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.UTXO> { $0.accountIndex == index }
                let d = FetchDescriptor<Storage.Entity.UTXO>(predicate: p)
                return try ctx.fetch(d)
            }
            await cache.set(key, result)
            return result
        }
        
        public func upsertAll(_ index: UInt32, utxos: [Transaction.Output.Unspent]) async throws {
            try Storage.Facade.withContext(container) { ctx in
                // Replace snapshot for the account.
                let p = #Predicate<Storage.Entity.UTXO> { $0.accountIndex == index }
                try ctx.delete(model: Storage.Entity.UTXO.self, where: p)
                
                for u in utxos {
                    let m = Storage.Entity.UTXO(transactionHash: u.previousTransactionHash.naturalOrder,
                                                outputIndex: u.previousTransactionOutputIndex,
                                                value: u.value,
                                                lockingScript: u.lockingScript,
                                                accountIndex: index)
                    ctx.insert(m)
                }
            }
            await cache.invalidate("a:\(index)")
        }
        
        public func spend(_ outs: [Transaction.Output.Unspent]) async throws {
            try Storage.Facade.withContext(container) { ctx in
                for u in outs {
                    let key = Storage.Entity.UTXO.makeKey(transactionHash: u.previousTransactionHash.naturalOrder,
                                                          outputIndex: u.previousTransactionOutputIndex)
                    let p = #Predicate<Storage.Entity.UTXO> { $0.key == key }
                    try ctx.delete(model: Storage.Entity.UTXO.self, where: p)
                }
            }
            await cache.clear()
        }
        
        public func clear(_ index: UInt32) async throws {
            try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.UTXO> { $0.accountIndex == index }
                try ctx.delete(model: Storage.Entity.UTXO.self, where: p)
            }
            await cache.invalidate("a:\(index)")
        }
    }
}

// Transactions
public extension Storage.Repository {
    actor Transactions {
        private let container: ModelContainer
        private let recentCache = TTLCache<String, [Storage.Entity.Transaction]>(defaultTTL: 300)
        
        public init(container: ModelContainer) { self.container = container }
        
        public func upsertDetailed(_ t: Transaction.Detailed, accountIndex: UInt32?) async throws {
            try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Transaction> { $0.hash == t.hash }
                if let ex = try ctx.fetch(FetchDescriptor(predicate: p)).first {
                    ex.raw = t.raw
                    ex.height = t.confirmations != nil && (t.confirmations ?? 0) > 0 ? t.blockTime : ex.height
                    ex.time = t.time
                    ex.isPending = (t.confirmations ?? 0) == 0
                    if let ai = accountIndex { ex.accountIndex = ai }
                    ctx.insert(ex)
                } else {
                    let m = Storage.Entity.Transaction(hash: t.hash,
                                                       raw: t.raw,
                                                       height: (t.confirmations ?? 0) > 0 ? t.blockTime : nil,
                                                       time: t.time,
                                                       fee: nil,
                                                       isPending: (t.confirmations ?? 0) == 0,
                                                       accountIndex: accountIndex)
                    ctx.insert(m)
                }
            }
            await recentCache.clear()
        }
        
        public func byHash(_ hash: Data) throws -> Storage.Entity.Transaction? {
            try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Transaction> { $0.hash == hash }
                return try ctx.fetch(FetchDescriptor(predicate: p)).first
            }
        }
        
        public func markConfirmed(_ hash: Data, height: UInt32?, time: UInt32?) async throws {
            try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Transaction> { $0.hash == hash }
                if let tx = try ctx.fetch(FetchDescriptor(predicate: p)).first {
                    tx.isPending = false
                    tx.height = height ?? tx.height
                    tx.time = time ?? tx.time
                    ctx.insert(tx)
                }
            }
            await recentCache.clear()
        }
        
        public func pending() throws -> [Storage.Entity.Transaction] {
            try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Transaction> { $0.isPending == true }
                return try ctx.fetch(FetchDescriptor(predicate: p))
            }
        }
        
        public func recent(limit: Int = 50) async throws -> [Storage.Entity.Transaction] {
            if let cached = await recentCache.get("recent:\(limit)") { return cached }
            let r = try Storage.Facade.withContext(container) { ctx in
                var d = FetchDescriptor<Storage.Entity.Transaction>(predicate: nil,
                                                                    sortBy: [SortDescriptor(\.time, order: .reverse)])
                d.fetchLimit = limit
                return try ctx.fetch(d)
            }
            await recentCache.set("recent:\(limit)", r)
            return r
        }
    }
}

// Accounts
public extension Storage.Repository {
    actor Accounts {
        private let container: ModelContainer
        
        public init(container: ModelContainer) { self.container = container }
        
        public func upsert(purpose: UInt32, coinType: UInt32, index: UInt32, label: String?) throws {
            try Storage.Facade.withContext(container) { ctx in
                let id = "\(purpose)-\(coinType)-\(index)"
                let p = #Predicate<Storage.Entity.Account> { $0.id == id }
                if let ex = try ctx.fetch(FetchDescriptor(predicate: p)).first {
                    ex.label = label
                    ctx.insert(ex)
                } else {
                    ctx.insert(Storage.Entity.Account(purpose: purpose, coinType: coinType, index: index, label: label))
                }
            }
        }
        
        public func byIndex(purpose: UInt32, coinType: UInt32, index: UInt32) throws -> Storage.Entity.Account? {
            try Storage.Facade.withContext(container) { ctx in
                let id = "\(purpose)-\(coinType)-\(index)"
                let p = #Predicate<Storage.Entity.Account> { $0.id == id }
                return try ctx.fetch(FetchDescriptor(predicate: p)).first
            }
        }
        
        public func all() throws -> [Storage.Entity.Account] {
            try Storage.Facade.withContext(container) { ctx in
                try ctx.fetch(FetchDescriptor<Storage.Entity.Account>())
            }
        }
    }
}

// Fees
public extension Storage.Repository {
    actor Fees {
        private let container: ModelContainer
        private let cache = TTLCache<String, UInt64>(defaultTTL: 600)
        
        public init(container: ModelContainer) { self.container = container }
        
        public func put(tier: Storage.Entity.Fee.Tier, satsPerByte: UInt64, ttl: TimeInterval = 600) async throws {
            try Storage.Facade.withContext(container) { ctx in
                let key = tier.rawValue
                let p = #Predicate<Storage.Entity.Fee> { $0.tier == key }
                if let ex = try ctx.fetch(FetchDescriptor(predicate: p)).first {
                    ex.satsPerByte = satsPerByte
                    ex.timestamp = .now
                    ctx.insert(ex)
                } else {
                    ctx.insert(Storage.Entity.Fee(tier: tier, satsPerByte: satsPerByte))
                }
            }
            await cache.set(tier.rawValue, satsPerByte, ttl: ttl)
        }
        
        public func latest(_ tier: Storage.Entity.Fee.Tier, maxAge: TimeInterval = 900) async throws -> UInt64? {
            if let v = await cache.get(tier.rawValue) { return v }
            let v = try Storage.Facade.withContext(container) { ctx in
                let key = tier.rawValue
                let p = #Predicate<Storage.Entity.Fee> { $0.tier == key }
                return try ctx.fetch(FetchDescriptor(predicate: p)).first
            }
            guard let m = v else { return nil }
            let age = Date().timeIntervalSince(m.timestamp)
            if age <= maxAge {
                await cache.set(tier.rawValue, m.satsPerByte, ttl: maxAge - age)
                return m.satsPerByte
            }
            return nil
        }
    }
}

// ServerHealth
public extension Storage.Repository {
    actor ServerHealth {
        private let container: ModelContainer
        private let cache = TTLCache<String, Storage.Entity.ServerHealth>(defaultTTL: 300)
        
        public init(container: ModelContainer) { self.container = container }
        
        public func recordProbe(url: URL, latency: TimeInterval?, healthy: Bool) async throws {
            try Storage.Facade.withContext(container) { ctx in
                let key = url.absoluteString
                let p = #Predicate<Storage.Entity.ServerHealth> { $0.url == key }
                let ms = latency.map { $0 * 1000 }
                if let ex = try ctx.fetch(FetchDescriptor(predicate: p)).first {
                    ex.latencyMs = ms
                    ex.status = healthy ? "healthy" : "unhealthy"
                    if healthy { ex.lastOK = .now; ex.failures = 0; ex.quarantineUntil = nil }
                    else { ex.failures += 1 }
                    ctx.insert(ex)
                } else {
                    ctx.insert(Storage.Entity.ServerHealth(url: key,
                                                           latencyMs: ms,
                                                           status: healthy ? "healthy" : "unhealthy",
                                                           failures: healthy ? 0 : 1,
                                                           quarantineUntil: nil,
                                                           lastOK: healthy ? .now : nil))
                }
            }
            await cache.invalidate(url.absoluteString)
        }
        
        public func bestPrimary(candidates: [URL]) throws -> URL? {
            try Storage.Facade.withContext(container) { ctx in
                let urls = Set(candidates.map(\.absoluteString))
                let p = #Predicate<Storage.Entity.ServerHealth> { urls.contains($0.url) && $0.quarantineUntil == nil && $0.status == "healthy" }
                let rows = try ctx.fetch(FetchDescriptor(predicate: p))
                let picked = rows
                    .sorted { ($0.latencyMs ?? .greatestFiniteMagnitude) < ($1.latencyMs ?? .greatestFiniteMagnitude) }
                    .first?.url
                return picked.flatMap(URL.init(string:))
            }
        }
        
        public func quarantine(_ url: URL, until: Date) async throws {
            try Storage.Facade.withContext(container) { ctx in
                let key = url.absoluteString
                let p = #Predicate<Storage.Entity.ServerHealth> { $0.url == key }
                if let ex = try ctx.fetch(FetchDescriptor(predicate: p)).first {
                    ex.quarantineUntil = until
                    ex.status = "unhealthy"
                    ctx.insert(ex)
                } else {
                    ctx.insert(Storage.Entity.ServerHealth(url: key, latencyMs: nil, status: "unhealthy", failures: 1, quarantineUntil: until, lastOK: nil))
                }
            }
            await cache.invalidate(url.absoluteString)
        }
        
        public func history(_ url: URL) throws -> Storage.Entity.ServerHealth? {
            try Storage.Facade.withContext(container) { ctx in
                let key = url.absoluteString
                let p = #Predicate<Storage.Entity.ServerHealth> { $0.url == key }
                return try ctx.fetch(FetchDescriptor(predicate: p)).first
            }
        }
    }
}

// Subscriptions
public extension Storage.Repository {
    actor Subscriptions {
        private let container: ModelContainer
        private let cache = TTLCache<String, Storage.Entity.Subscription>(defaultTTL: 600)
        
        public init(container: ModelContainer) { self.container = container }
        
        public func upsert(address: String, isActive: Bool, lastStatus: String?) async throws {
            try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Subscription> { $0.address == address }
                if let ex = try ctx.fetch(FetchDescriptor(predicate: p)).first {
                    ex.isActive = isActive
                    ex.lastStatus = lastStatus
                    ex.lastUpdated = .now
                    ctx.insert(ex)
                } else {
                    ctx.insert(Storage.Entity.Subscription(address: address, isActive: isActive, lastStatus: lastStatus))
                }
            }
            await cache.invalidate(address)
        }
        
        public func byAddress(_ address: String) async throws -> Storage.Entity.Subscription? {
            if let s = await cache.get(address) { return s }
            let s = try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Subscription> { $0.address == address }
                return try ctx.fetch(FetchDescriptor(predicate: p)).first
            }
            if let s { await cache.set(address, s) }
            return s
        }
        
        public func deactivate(_ address: String) async throws {
            try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Subscription> { $0.address == address }
                if let ex = try ctx.fetch(FetchDescriptor(predicate: p)).first {
                    ex.isActive = false
                    ex.lastUpdated = .now
                    ctx.insert(ex)
                }
            }
            await cache.invalidate(address)
        }
    }
}

extension Storage.Repository {
    public enum Error: Swift.Error {
        case fetchFailed(Swift.Error)
        case saveFailed(Swift.Error)
    }
}

#endif
