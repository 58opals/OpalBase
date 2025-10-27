// Storage+Repository.swift

import Foundation

extension Storage {
    public enum Repository {}
}

extension Storage.Repository {
    public actor TimeToLiveCache<Key: Hashable & Sendable, Value: Sendable> {
        private struct Item { let value: Value; let expiry: Date }
        private var items: [Key: Item] = [:]
        private let defaultTimeToLive: TimeInterval
        public init(defaultTimeToLive: TimeInterval) { self.defaultTimeToLive = defaultTimeToLive }
        public func loadValue(for key: Key) -> Value? {
            guard let item = items[key] else { return nil }
            if item.expiry > Date() { return item.value }
            items[key] = nil; return nil
        }
        public func set(_ key: Key, _ value: Value, timeToLive: TimeInterval? = nil) {
            items[key] = .init(value: value, expiry: Date().addingTimeInterval(timeToLive ?? defaultTimeToLive))
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
        private let tipCache = TimeToLiveCache<String, Storage.Row.Header>(defaultTimeToLive: 600)
        public init(container: ModelContainer) { self.container = container }
        
        public func loadTip() async throws -> Storage.Row.Header? {
            if let cached = await tipCache.loadValue(for: "tip") { return cached }
            let found: Storage.Entity.HeaderModel? = try Storage.Facade.performWithContext(container) { context in
                var description = FetchDescriptor<Storage.Entity.HeaderModel>(predicate: nil,
                                                                              sortBy: [SortDescriptor(\.height, order: .reverse)])
                description.fetchLimit = 1
                return try context.fetch(description).first
            }
            if let h = found?.row { await tipCache.set("tip", h); return h }
            return nil
        }
        
        public func loadByHeight(_ height: UInt32) throws -> Storage.Row.Header? {
            try Storage.Facade.performWithContext(container) { context in
                let predicate = #Predicate<Storage.Entity.HeaderModel> { $0.height == height }
                return try context.fetch(FetchDescriptor(predicate: predicate)).first?.row
            }
        }
        
        public func upsertRange(_ entries: [(height: UInt32, header: Block.Header, hash: Data)]) async throws {
            try Storage.Facade.performWithContext(container) { context in
                for (height, header, hash) in entries {
                    let predicate = #Predicate<Storage.Entity.HeaderModel> { $0.height == height }
                    if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                        existing.version = header.version
                        existing.previousBlockHash = header.previousBlockHash
                        existing.merkleRoot = header.merkleRoot
                        existing.time = header.time
                        existing.bits = header.bits
                        existing.nonce = header.nonce
                        existing.hash = hash
                    } else {
                        context.insert(Storage.Entity.HeaderModel(height: height,
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
        
        
        public func performWithHeader<T: Sendable>(height: UInt32,
                                                   _ body: (Storage.Entity.HeaderModel) throws -> T) rethrows -> T? {
            try Storage.Facade.performWithContext(container) { context in
                let predicate = #Predicate<Storage.Entity.HeaderModel> { $0.height == height }
                guard let m = try context.fetch(FetchDescriptor(predicate: predicate)).first else { return nil }
                return try body(m)
            }
        }
    }
}

// UTXOs
extension Storage.Repository {
    public actor UTXOs {
        private let container: ModelContainer
        private let cache = TimeToLiveCache<String, [Storage.Row.UTXO]>(defaultTimeToLive: 300)
        public init(container: ModelContainer) { self.container = container }
        
        public func loadForAccount(_ index: UInt32) async throws -> [Storage.Row.UTXO] {
            let key = "a:\(index)"
            if let cached = await cache.loadValue(for: key) { return cached }
            let rows: [Storage.Row.UTXO] = try Storage.Facade.performWithContext(container) { context in
                let predicate = #Predicate<Storage.Entity.UTXOModel> { $0.accountIndex == index }
                return try context.fetch(FetchDescriptor(predicate: predicate)).map(\.row)
            }
            await cache.set(key, rows)
            return rows
        }
        
        public func upsertAll(_ index: UInt32, utxos: [Transaction.Output.Unspent]) async throws {
            try Storage.Facade.performWithContext(container) { context in
                let predicate = #Predicate<Storage.Entity.UTXOModel> { $0.accountIndex == index }
                try context.delete(model: Storage.Entity.UTXOModel.self, where: predicate)
                
                for utxo in utxos {
                    let model = Storage.Entity.UTXOModel(transactionHash: utxo.previousTransactionHash,
                                                         outputIndex: utxo.previousTransactionOutputIndex,
                                                         value: utxo.value,
                                                         lockingScript: utxo.lockingScript,
                                                         accountIndex: index)
                    context.insert(model)
                }
            }
            await cache.invalidate("a:\(index)")
        }
        
        public func spend(_ utxos: [Transaction.Output.Unspent]) async throws {
            let affectedIndices: Set<UInt32> = try Storage.Facade.performWithContext(container) { context in
                var indices = Set<UInt32>()
                for utxo in utxos {
                    let key = Storage.Entity.UTXOModel.makeKey(
                        transactionHash: utxo.previousTransactionHash,
                        outputIndex: utxo.previousTransactionOutputIndex
                    )
                    let predicate = #Predicate<Storage.Entity.UTXOModel> { $0.key == key }
                    if let utxo = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                        indices.insert(utxo.accountIndex)
                        context.delete(utxo)
                    }
                }
                return indices
            }
            for affectedIndex in affectedIndices { await cache.invalidate("a:\(affectedIndex)") }
        }
        
        public func clear(_ index: UInt32) async throws {
            try Storage.Facade.performWithContext(container) { context in
                let predicate = #Predicate<Storage.Entity.UTXOModel> { $0.accountIndex == index }
                try context.delete(model: Storage.Entity.UTXOModel.self, where: predicate)
            }
            await cache.invalidate("a:\(index)")
        }
    }
}

// Transactions
extension Storage.Repository {
    public actor Transactions {
        private let container: ModelContainer
        private let recentCache = TimeToLiveCache<String, [Storage.Row.Transaction]>(defaultTimeToLive: 300)
        public init(container: ModelContainer) { self.container = container }
        
        public func loadByHash(_ hash: Transaction.Hash) throws -> Storage.Row.Transaction? {
            try Storage.Facade.performWithContext(container) { context in
                let hashData = hash.naturalOrder
                let predicate = #Predicate<Storage.Entity.TransactionModel> { $0.hash == hashData }
                return try context.fetch(FetchDescriptor(predicate: predicate)).first?.row
            }
        }
        
        public func loadPending() throws -> [Storage.Row.Transaction] {
            try Storage.Facade.performWithContext(container) { context in
                let predicate = #Predicate<Storage.Entity.TransactionModel> { $0.isPending == true }
                return try context.fetch(FetchDescriptor(predicate: predicate)).map(\.row)
            }
        }
        
        public func loadRecent(limit: Int = 50) async throws -> [Storage.Row.Transaction] {
            if let cached = await recentCache.loadValue(for: "recent:\(limit)") { return cached }
            let recentTransactions: [Storage.Row.Transaction] = try Storage.Facade.performWithContext(container) { context in
                var descriptor = FetchDescriptor<Storage.Entity.TransactionModel>(predicate: nil,
                                                                                  sortBy: [SortDescriptor(\.time, order: .reverse)])
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor).map(\.row)
            }
            await recentCache.set("recent:\(limit)", recentTransactions)
            return recentTransactions
        }
    }
}

// Accounts
extension Storage.Repository {
    public actor Accounts {
        private let container: ModelContainer
        
        public init(container: ModelContainer) { self.container = container }
        
        public func upsert(purpose: UInt32, coinType: UInt32, index: UInt32, label: String?) throws {
            try Storage.Facade.performWithContext(container) { context in
                let id = "\(purpose)-\(coinType)-\(index)"
                let predicate = #Predicate<Storage.Entity.AccountModel> { $0.id == id }
                if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                    existing.label = label
                    context.insert(existing)
                } else {
                    context.insert(Storage.Entity.AccountModel(purpose: purpose, coinType: coinType, index: index, label: label))
                }
            }
        }
        
        public func loadByIndex(purpose: UInt32, coinType: UInt32, index: UInt32) throws -> Storage.Entity.AccountModel? {
            try Storage.Facade.performWithContext(container) { context in
                let id = "\(purpose)-\(coinType)-\(index)"
                let predicate = #Predicate<Storage.Entity.AccountModel> { $0.id == id }
                return try context.fetch(FetchDescriptor(predicate: predicate)).first
            }
        }
        
        public func loadAllAccounts() throws -> [Storage.Entity.AccountModel] {
            try Storage.Facade.performWithContext(container) { context in
                try context.fetch(FetchDescriptor<Storage.Entity.AccountModel>())
            }
        }
    }
}

// Fees
extension Storage.Repository {
    public actor Fees {
        public enum Error: Swift.Error, Sendable, Equatable {
            case conflict(expected: UInt64?, actual: UInt64?)
            case storage(String)
        }
        
        private let container: ModelContainer
        private let cache = TimeToLiveCache<String, Storage.Row.Fee>(defaultTimeToLive: 600)
        
        public init(container: ModelContainer) { self.container = container }
        
        public func put(tier: Storage.Entity.FeeModel.Tier,
                        satsPerByte: UInt64,
                        timeToLive: TimeInterval = 600,
                        expectedVersion: UInt64? = nil) async throws -> Storage.Row.Fee {
            let now = Date()
            let row: Storage.Row.Fee
            do {
                row = try Storage.Facade.performWithContext(container) { context in
                    let key = tier.rawValue
                    let predicate = #Predicate<Storage.Entity.FeeModel> { $0.tier == key }
                    if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                        if let expectedVersion, existing.version != expectedVersion {
                            throw Error.conflict(expected: expectedVersion, actual: existing.version)
                        }
                        existing.satsPerByte = satsPerByte
                        existing.timestamp = now
                        existing.version &+= 1
                        context.insert(existing)
                        return existing.row
                    }
                    if let expectedVersion {
                        throw Error.conflict(expected: expectedVersion, actual: nil)
                    }
                    let created = Storage.Entity.FeeModel(tier: tier,
                                                          satsPerByte: satsPerByte,
                                                          timestamp: now,
                                                          version: 0)
                    context.insert(created)
                    return created.row
                }
            } catch let conflict as Error {
                throw conflict
            } catch {
                throw Error.storage(String(describing: error))
            }
            await cache.set(tier.rawValue, row, timeToLive: max(0, timeToLive))
            
            return row
        }
        
        public func loadLatest(_ tier: Storage.Entity.FeeModel.Tier,
                               maxAge: TimeInterval = 900) async throws -> Storage.Row.Fee? {
            if let cached = await cache.loadValue(for: tier.rawValue) { return cached }
            let model: Storage.Entity.FeeModel?
            do {
                model = try Storage.Facade.performWithContext(container) { context in
                    let key = tier.rawValue
                    let predicate = #Predicate<Storage.Entity.FeeModel> { $0.tier == key }
                    return try context.fetch(FetchDescriptor(predicate: predicate)).first
                }
            } catch {
                throw Error.storage(String(describing: error))
            }
            guard let stored = model else { return nil }
            let row = stored.row
            let age = Date().timeIntervalSince(row.timestamp)
            guard age <= maxAge else {
                await cache.invalidate(tier.rawValue)
                return nil
            }
            await cache.set(tier.rawValue, row, timeToLive: max(0, maxAge - age))
            return row
        }
        
        public func remove(_ tier: Storage.Entity.FeeModel.Tier,
                           expectedVersion: UInt64? = nil) async throws {
            do {
                try Storage.Facade.performWithContext(container) { context in
                    let key = tier.rawValue
                    let predicate = #Predicate<Storage.Entity.FeeModel> { $0.tier == key }
                    if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                        if let expectedVersion, existing.version != expectedVersion {
                            throw Error.conflict(expected: expectedVersion, actual: existing.version)
                        }
                        context.delete(existing)
                    } else if let expectedVersion {
                        throw Error.conflict(expected: expectedVersion, actual: nil)
                    }
                }
            } catch let conflict as Error {
                throw conflict
            } catch {
                throw Error.storage(String(describing: error))
            }
            await cache.invalidate(tier.rawValue)
        }
    }
}

// ServerHealth
extension Storage.Repository {
    public actor ServerHealth {
        private let container: ModelContainer
        private let cache = TimeToLiveCache<String, Storage.Row.ServerHealth>(defaultTimeToLive: 300)
        
        public init(container: ModelContainer) { self.container = container }
        
        public func recordProbe(url: URL, latency: TimeInterval?, healthy: Bool) async throws {
            do {
                try Storage.Facade.performWithContext(container) { context in
                    let key = url.absoluteString
                    let predicate = #Predicate<Storage.Entity.ServerHealthModel> { $0.url == key }
                    let ms = latency.map { $0 * 1000 }
                    if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                        existing.latencyMs = ms
                        existing.status = healthy ? "healthy" : "unhealthy"
                        if healthy {
                            existing.lastOK = .now
                            existing.failures = 0
                            existing.quarantineUntil = nil
                        } else {
                            existing.failures += 1
                        }
                        context.insert(existing)
                    } else {
                        context.insert(Storage.Entity.ServerHealthModel(url: key,
                                                                        latencyMs: ms,
                                                                        status: healthy ? "healthy" : "unhealthy",
                                                                        failures: healthy ? 0 : 1,
                                                                        quarantineUntil: nil,
                                                                        lastOK: healthy ? .now : nil))
                    }
                }
            } catch {
                throw Error(operation: "recordProbe", reason: String(describing: error))
            }
            await cache.invalidate(url.absoluteString)
        }
        
        public func loadBestPrimary(candidates: [URL]) throws -> URL? {
            do {
                return try Storage.Facade.performWithContext(container) { context in
                    let urls = Set(candidates.map(\.absoluteString))
                    let predicate = #Predicate<Storage.Entity.ServerHealthModel> { urls.contains($0.url) && $0.quarantineUntil == nil && $0.status == "healthy" }
                    let rows = try context.fetch(FetchDescriptor(predicate: predicate)).map(\.row)
                    return rows
                        .sorted { ($0.latencyMs ?? .greatestFiniteMagnitude) < ($1.latencyMs ?? .greatestFiniteMagnitude) }
                        .first
                        .flatMap { URL(string: $0.url) }
                }
            } catch {
                throw Error(operation: "bestPrimary", reason: String(describing: error))
            }
        }
        
        public func quarantine(_ url: URL, until: Date) async throws {
            do {
                try Storage.Facade.performWithContext(container) { context in
                    let key = url.absoluteString
                    let predicate = #Predicate<Storage.Entity.ServerHealthModel> { $0.url == key }
                    if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                        existing.quarantineUntil = until
                        existing.status = "unhealthy"
                        context.insert(existing)
                    } else {
                        context.insert(Storage.Entity.ServerHealthModel(url: key,
                                                                        latencyMs: nil,
                                                                        status: "unhealthy",
                                                                        failures: 1,
                                                                        quarantineUntil: until,
                                                                        lastOK: nil))
                    }
                }
            } catch {
                throw Error(operation: "quarantine", reason: String(describing: error))
            }
            await cache.invalidate(url.absoluteString)
        }
        
        public func release(_ url: URL, failures: Int, condition: String) async throws {
            do {
                try Storage.Facade.performWithContext(container) { context in
                    let key = url.absoluteString
                    let predicate = #Predicate<Storage.Entity.ServerHealthModel> { $0.url == key }
                    if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                        existing.quarantineUntil = nil
                        existing.failures = failures
                        existing.status = condition
                        context.insert(existing)
                    } else {
                        context.insert(Storage.Entity.ServerHealthModel(url: key,
                                                                        latencyMs: nil,
                                                                        status: condition,
                                                                        failures: failures,
                                                                        quarantineUntil: nil,
                                                                        lastOK: nil))
                    }
                }
            } catch {
                throw Error(operation: "release", reason: String(describing: error))
            }
            await cache.invalidate(url.absoluteString)
        }
        
        public func soften(_ url: URL,
                           failures: Int,
                           condition: String,
                           quarantineUntil: Date?) async throws
        {
            do {
                try Storage.Facade.performWithContext(container) { context in
                    let key = url.absoluteString
                    let predicate = #Predicate<Storage.Entity.ServerHealthModel> { $0.url == key }
                    if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                        existing.failures = failures
                        existing.status = condition
                        existing.quarantineUntil = quarantineUntil
                        context.insert(existing)
                    } else {
                        context.insert(Storage.Entity.ServerHealthModel(url: key,
                                                                        latencyMs: nil,
                                                                        status: condition,
                                                                        failures: failures,
                                                                        quarantineUntil: quarantineUntil,
                                                                        lastOK: nil))
                    }
                }
            } catch {
                throw Error(operation: "soften", reason: String(describing: error))
            }
            await cache.invalidate(url.absoluteString)
        }
        
        public func loadHistory(_ url: URL) throws -> Storage.Row.ServerHealth? {
            do {
                return try Storage.Facade.performWithContext(container) { context in
                    let key = url.absoluteString
                    let predicate = #Predicate<Storage.Entity.ServerHealthModel> { $0.url == key }
                    return try context.fetch(FetchDescriptor(predicate: predicate)).first?.row
                }
            } catch {
                throw Error(operation: "history", reason: String(describing: error))
            }
        }
    }
}

extension Storage.Repository.ServerHealth {
    public struct Error: Swift.Error, Sendable, Equatable {
        public let operation: String
        public let reason: String
    }
}

// Subscriptions
extension Storage.Repository {
    public actor Subscriptions {
        private let container: ModelContainer
        private let cache = TimeToLiveCache<String, Storage.Row.Subscription>(defaultTimeToLive: 600)
        
        public init(container: ModelContainer) { self.container = container }
        
        public func upsert(address: String, isActive: Bool, lastStatus: String?) async throws {
            try Storage.Facade.performWithContext(container) { context in
                let predicate = #Predicate<Storage.Entity.SubscriptionModel> { $0.address == address }
                if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                    existing.isActive = isActive
                    existing.lastStatus = lastStatus
                    existing.lastUpdated = .now
                    context.insert(existing)
                } else {
                    context.insert(Storage.Entity.SubscriptionModel(address: address,
                                                                    isActive: isActive,
                                                                    lastStatus: lastStatus))
                }
            }
            await cache.invalidate(address)
        }
        
        public func loadByAddress(_ address: String) async throws -> Storage.Row.Subscription? {
            if let subscription = await cache.loadValue(for: address) { return subscription }
            let row = try Storage.Facade.performWithContext(container) { context in
                let predicate = #Predicate<Storage.Entity.SubscriptionModel> { $0.address == address }
                return try context.fetch(FetchDescriptor(predicate: predicate)).first?.row
            }
            if let row { await cache.set(address, row) }
            return row
        }
        
        public func deactivate(_ address: String) async throws {
            try Storage.Facade.performWithContext(container) { context in
                let predicate = #Predicate<Storage.Entity.SubscriptionModel> { $0.address == address }
                if let existing = try context.fetch(FetchDescriptor(predicate: predicate)).first {
                    existing.isActive = false
                    existing.lastUpdated = .now
                    context.insert(existing)
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
