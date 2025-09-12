// Storage+Repository.swift

import Foundation

extension Storage {
    public enum Repository {}
}

extension Storage.Repository {
    public actor TTLCache<Key: Hashable & Sendable, Value: Sendable> {
        private struct Item { let value: Value; let expiry: Date }
        private var items: [Key: Item] = [:]
        private let defaultTTL: TimeInterval
        public init(defaultTTL: TimeInterval) { self.defaultTTL = defaultTTL }
        public func get(_ key: Key) -> Value? {
            guard let item = items[key] else { return nil }
            if item.expiry > Date() { return item.value }
            items[key] = nil; return nil
        }
        public func set(_ key: Key, _ value: Value, ttl: TimeInterval? = nil) {
            items[key] = .init(value: value, expiry: Date().addingTimeInterval(ttl ?? defaultTTL))
        }
        public func invalidate(_ key: Key) { items[key] = nil }
        public func clear() { items.removeAll() }
    }
}

#if canImport(SwiftData)
import SwiftData

// Headers
extension Storage.Repository {
    public actor Headers {
        private let container: ModelContainer
        private let tipCache = TTLCache<String, Storage.Row.Header>(defaultTTL: 600)
        public init(container: ModelContainer) { self.container = container }
        
        public func tip() async throws -> Storage.Row.Header? {
            if let cached = await tipCache.get("tip") { return cached }
            let found: Storage.Entity.Header? = try Storage.Facade.withContext(container) { ctx in
                var desc = FetchDescriptor<Storage.Entity.Header>(predicate: nil,
                                                                  sortBy: [SortDescriptor(\.height, order: .reverse)])
                desc.fetchLimit = 1
                return try ctx.fetch(desc).first
            }
            if let h = found?.row { await tipCache.set("tip", h); return h }
            return nil
        }
        
        public func byHeight(_ height: UInt32) throws -> Storage.Row.Header? {
            try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Header> { $0.height == height }
                return try ctx.fetch(FetchDescriptor(predicate: p)).first?.row
            }
        }
        
        public func upsertRange(_ entries: [(height: UInt32, header: Block.Header, hash: Data)]) async throws {
            try Storage.Facade.withContext(container) { ctx in
                for (height, header, hash) in entries {            // destructure tuple
                    let p = #Predicate<Storage.Entity.Header> { $0.height == height }
                    if let existing = try ctx.fetch(FetchDescriptor(predicate: p)).first {
                        existing.version = header.version
                        existing.previousBlockHash = header.previousBlockHash
                        existing.merkleRoot = header.merkleRoot
                        existing.time = header.time
                        existing.bits = header.bits
                        existing.nonce = header.nonce
                        existing.hash = hash
                    } else {
                        ctx.insert(Storage.Entity.Header(height: height,
                                                         version: header.version,
                                                         previousBlockHash: header.previousBlockHash,
                                                         merkleRoot: header.merkleRoot,
                                                         time: header.time,
                                                         bits: header.bits,
                                                         nonce: header.nonce,
                                                         hash: hash))
                    }
                }
            }
            await tipCache.invalidate("tip")
        }
        
        
        public func withHeader<T: Sendable>(height: UInt32,
                                            _ body: (Storage.Entity.Header) throws -> T) rethrows -> T? {
            try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Header> { $0.height == height }
                guard let m = try ctx.fetch(FetchDescriptor(predicate: p)).first else { return nil }
                return try body(m)
            }
        }
    }
}


// UTXOs
extension Storage.Repository {
    public actor UTXOs {
        private let container: ModelContainer
        private let cache = TTLCache<String, [Storage.Row.UTXO]>(defaultTTL: 300)
        public init(container: ModelContainer) { self.container = container }
        
        public func forAccount(_ index: UInt32) async throws -> [Storage.Row.UTXO] {
            let key = "a:\(index)"
            if let cached = await cache.get(key) { return cached }
            let rows: [Storage.Row.UTXO] = try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.UTXO> { $0.accountIndex == index }
                return try ctx.fetch(FetchDescriptor(predicate: p)).map(\.row)
            }
            await cache.set(key, rows)
            return rows
        }
        
        public func upsertAll(_ index: UInt32, utxos: [Transaction.Output.Unspent]) async throws {
            try Storage.Facade.withContext(container) { ctx in
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
            let affected: Set<UInt32> = try Storage.Facade.withContext(container) { ctx in
                var a = Set<UInt32>()
                for u in outs {
                    let key = Storage.Entity.UTXO.makeKey(
                        transactionHash: u.previousTransactionHash.naturalOrder,
                        outputIndex: u.previousTransactionOutputIndex
                    )
                    let p = #Predicate<Storage.Entity.UTXO> { $0.key == key }
                    if let utxo = try ctx.fetch(FetchDescriptor(predicate: p)).first {
                        a.insert(utxo.accountIndex)
                        ctx.delete(utxo)
                    }
                }
                return a
            }
            for ai in affected { await cache.invalidate("a:\(ai)") }
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
extension Storage.Repository {
    public actor Transactions {
        private let container: ModelContainer
        private let recentCache = TTLCache<String, [Storage.Row.Transaction]>(defaultTTL: 300)
        public init(container: ModelContainer) { self.container = container }
        
        public func byHash(_ hash: Data) throws -> Storage.Row.Transaction? {
            try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Transaction> { $0.hash == hash }
                return try ctx.fetch(FetchDescriptor(predicate: p)).first?.row
            }
        }
        
        public func pending() throws -> [Storage.Row.Transaction] {
            try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Transaction> { $0.isPending == true }
                return try ctx.fetch(FetchDescriptor(predicate: p)).map(\.row)
            }
        }
        
        public func recent(limit: Int = 50) async throws -> [Storage.Row.Transaction] {
            if let cached = await recentCache.get("recent:\(limit)") { return cached }
            let r: [Storage.Row.Transaction] = try Storage.Facade.withContext(container) { ctx in
                var d = FetchDescriptor<Storage.Entity.Transaction>(predicate: nil,
                                                                    sortBy: [SortDescriptor(\.time, order: .reverse)])
                d.fetchLimit = limit
                return try ctx.fetch(d).map(\.row)
            }
            await recentCache.set("recent:\(limit)", r)
            return r
        }
    }
}


// Accounts
extension Storage.Repository {
    public actor Accounts {
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
extension Storage.Repository {
    public actor Fees {
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
extension Storage.Repository {
    public actor ServerHealth {
        private let container: ModelContainer
        private let cache = TTLCache<String, Storage.Row.ServerHealth>(defaultTTL: 300)
        
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
                let rows = try ctx.fetch(FetchDescriptor(predicate: p)).map(\.row)
                return rows
                    .sorted { ($0.latencyMs ?? .greatestFiniteMagnitude) < ($1.latencyMs ?? .greatestFiniteMagnitude) }
                    .first
                    .flatMap { URL(string: $0.url) }
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
        
        public func history(_ url: URL) throws -> Storage.Row.ServerHealth? {
            try Storage.Facade.withContext(container) { ctx in
                let key = url.absoluteString
                let p = #Predicate<Storage.Entity.ServerHealth> { $0.url == key }
                return try ctx.fetch(FetchDescriptor(predicate: p)).first?.row
            }
        }
    }
}

// Subscriptions
extension Storage.Repository {
    public actor Subscriptions {
        private let container: ModelContainer
        private let cache = TTLCache<String, Storage.Row.Subscription>(defaultTTL: 600)
        
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
        
        public func byAddress(_ address: String) async throws -> Storage.Row.Subscription? {
            if let s = await cache.get(address) { return s }
            let row = try Storage.Facade.withContext(container) { ctx in
                let p = #Predicate<Storage.Entity.Subscription> { $0.address == address }
                return try ctx.fetch(FetchDescriptor(predicate: p)).first?.row
            }
            if let row { await cache.set(address, row) }
            return row
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
