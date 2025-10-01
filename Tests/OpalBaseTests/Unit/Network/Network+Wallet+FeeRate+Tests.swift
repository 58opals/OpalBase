import Foundation
import Testing
@testable import OpalBase

@Suite("Network Wallet Fee Rate", .tags(.unit, .policy, .network))
struct NetworkWalletFeeRateSuite {
    @Test("restores cached rate when persistence primed", .tags(.unit, .policy, .network))
    func restoresCachedRateFromPersistence() async throws {
        let persistence = InMemoryFeePersistence()
        await persistence.prime(tier: .fast, value: 142, timestamp: Date(), version: 3)
        
        let subject = Network.Wallet.FeeRate(
            rateProvider: { _ in throw FixtureError.unexpectedFetch },
            cacheThreshold: 60,
            smoothingAlpha: 0,
            persistenceWindow: 120,
            persistence: await persistence.adapter
        )
        
        let restored = try await subject.fetchRecommendedFeeRate(for: .fast)
        #expect(restored == 142)
    }
    
    @Test("invalidates stale caches after gateway events", .tags(.unit, .policy, .network))
    func invalidatesStaleCacheOnGatewayEvent() async throws {
        let persistence = InMemoryFeePersistence()
        let provider = SequencedRateProvider(values: [110, 210])
        
        let subject = Network.Wallet.FeeRate(
            rateProvider: { tier in try await provider.next(for: tier) },
            cacheThreshold: 1,
            smoothingAlpha: 0,
            persistenceWindow: 30,
            persistence: await persistence.adapter
        )
        
        let initial = try await subject.fetchRecommendedFeeRate(for: .fast)
        #expect(initial == 110)
        
        try await subject.record(event: .headersPinged(Date().addingTimeInterval(90)))
        
        let removals = await persistence.recordedRemovals()
        #expect(removals.contains { $0.tier == .fast })
        
        let refreshed = try await subject.fetchRecommendedFeeRate(for: .fast)
        #expect(refreshed == 210)
    }
    
    @Test("ignores persisted snapshots beyond retention window", .tags(.unit, .policy, .network))
    func ignoresSnapshotsOutsidePersistenceWindow() async throws {
        let persistence = InMemoryFeePersistence()
        let provider = SequencedRateProvider(values: [330])
        
        await persistence.prime(
            tier: .fast,
            value: 25,
            timestamp: Date().addingTimeInterval(-600),
            version: 5
        )
        
        let subject = Network.Wallet.FeeRate(
            rateProvider: { tier in try await provider.next(for: tier) },
            cacheThreshold: 60,
            smoothingAlpha: 0,
            persistenceWindow: 5,
            persistence: await persistence.adapter
        )
        
        let measured = try await subject.fetchRecommendedFeeRate(for: .fast)
        #expect(measured == 330)
        
        let stored = await persistence.snapshot(for: .fast)
        #expect(stored?.value == 330)
        #expect((stored?.version ?? 0) >= 5)
    }
}

private enum FixtureError: Swift.Error, Sendable {
    case unexpectedFetch
}

private actor SequencedRateProvider {
    enum Error: Swift.Error, Sendable {
        case exhausted
    }
    
    private var values: [UInt64]
    
    init(values: [UInt64]) {
        self.values = values
    }
    
    func next(for _: Network.Wallet.FeeRate.Tier) async throws -> UInt64 {
        guard !values.isEmpty else { throw Error.exhausted }
        return values.removeFirst()
    }
}

private actor InMemoryFeePersistence {
    struct Record: Sendable {
        var value: UInt64
        var timestamp: Date
        var version: UInt64
    }
    
    struct Removal: Sendable, Equatable {
        let tier: Network.Wallet.FeeRate.Tier
        let expectedVersion: UInt64?
    }
    
    private var storage: [Network.Wallet.FeeRate.Tier: Record] = [:]
    private var removals: [Removal] = []
    
    var adapter: Network.Wallet.FeeRate.Persistence {
        let actor = self
        return .init(
            loader: { tier, maxAge in try await actor.load(tier: tier, maxAge: maxAge) },
            writer: { tier, value, _, expected in try await actor.store(tier: tier, value: value, expectedVersion: expected) },
            remover: { tier, expected in try await actor.remove(tier: tier, expectedVersion: expected) }
        )
    }
    
    func prime(
        tier: Network.Wallet.FeeRate.Tier,
        value: UInt64,
        timestamp: Date,
        version: UInt64
    ) {
        storage[tier] = Record(value: value, timestamp: timestamp, version: version)
    }
    
    func load(
        tier: Network.Wallet.FeeRate.Tier,
        maxAge: TimeInterval
    ) throws -> Network.Wallet.FeeRate.Persistence.Snapshot? {
        guard let record = storage[tier] else { return nil }
        guard maxAge <= 0 || Date().timeIntervalSince(record.timestamp) <= maxAge else { return nil }
        return .init(
            tier: tier,
            value: record.value,
            timestamp: record.timestamp,
            version: record.version
        )
    }
    
    func store(
        tier: Network.Wallet.FeeRate.Tier,
        value: UInt64,
        expectedVersion: UInt64?
    ) throws -> Network.Wallet.FeeRate.Persistence.Snapshot {
        let now = Date()
        if var existing = storage[tier] {
            if let expectedVersion, existing.version != expectedVersion {
                throw Network.Wallet.FeeRate.Persistence.Error.conflict(
                    expected: expectedVersion,
                    actual: existing.version
                )
            }
            existing.value = value
            existing.timestamp = now
            existing.version &+= 1
            storage[tier] = existing
            return .init(
                tier: tier,
                value: existing.value,
                timestamp: existing.timestamp,
                version: existing.version
            )
        }
        
        if let expectedVersion {
            throw Network.Wallet.FeeRate.Persistence.Error.conflict(expected: expectedVersion, actual: nil)
        }
        
        let record = Record(value: value, timestamp: now, version: 0)
        storage[tier] = record
        return .init(
            tier: tier,
            value: record.value,
            timestamp: record.timestamp,
            version: record.version
        )
    }
    
    func remove(
        tier: Network.Wallet.FeeRate.Tier,
        expectedVersion: UInt64?
    ) throws {
        guard let record = storage[tier] else {
            if let expectedVersion {
                throw Network.Wallet.FeeRate.Persistence.Error.conflict(expected: expectedVersion, actual: nil)
            }
            return
        }
        
        if let expectedVersion, record.version != expectedVersion {
            throw Network.Wallet.FeeRate.Persistence.Error.conflict(
                expected: expectedVersion,
                actual: record.version
            )
        }
        
        storage.removeValue(forKey: tier)
        removals.append(Removal(tier: tier, expectedVersion: expectedVersion))
    }
    
    func recordedRemovals() -> [Removal] {
        removals
    }
    
    func snapshot(for tier: Network.Wallet.FeeRate.Tier) -> Network.Wallet.FeeRate.Persistence.Snapshot? {
        guard let record = storage[tier] else { return nil }
        return .init(
            tier: tier,
            value: record.value,
            timestamp: record.timestamp,
            version: record.version
        )
    }
}
