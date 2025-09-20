import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("FulcrumPool Reconnection")
struct FulcrumPoolTests {
    @Test func testReconnectBringsOfflineServerOnline() async throws {
        let pool = try await Network.Wallet.FulcrumPool()
        #expect(await pool.currentStatus == .offline)
        
        let stream = await pool.observeStatus()
        var iterator = stream.makeAsyncIterator()
        let initial = await iterator.next()
        #expect(initial == .offline)
        
        async let reconnection = pool.reconnect()
        
        let connecting = await iterator.next()
        _ = try await reconnection
        let final = await iterator.next()
        
        #expect(connecting == .connecting)
        #expect(final == .online)
        #expect(await pool.currentStatus == .online)
    }
    
    @Test func testPoolThrowsWhenNoServerResponds() async throws {
        let pool = try await Network.Wallet.FulcrumPool(urls: ["wss://invalid.example.invalid:50004"])
        
        await #expect(throws: Network.Wallet.Error.noHealthyServer) {
            _ = try await pool.acquireFulcrum()
        }
    }
    
    @Test func testServerHealthPersistsMetrics() async throws {
        let storage = try Storage.Facade(configuration: .memory)
        let repository = await storage.serverHealth
        let monitor = Network.Wallet.FulcrumPool.ServerHealth(repository: repository)
        let endpoint = try #require(URL(string: "wss://example.org:50002"))
        
        let retryDate = Date().addingTimeInterval(5)
        let failure = try await monitor.recordFailure(for: endpoint, retryAt: retryDate)
        #expect(failure.failures == 1)
        let quarantine = try #require(failure.quarantineUntil)
        #expect(quarantine >= retryDate)
        
        let storedFailure = try await repository.history(endpoint)
        #expect(storedFailure?.failures == 1)
        #expect(storedFailure?.quarantineUntil != nil)
        
        let success = try await monitor.recordSuccess(for: endpoint, latency: 0.25)
        #expect(success.failures == 0)
        #expect(success.quarantineUntil == nil)
        
        let storedSuccess = try await repository.history(endpoint)
        #expect(storedSuccess?.failures == 0)
        #expect(storedSuccess?.quarantineUntil == nil)
        let latency = try #require(storedSuccess?.latencyMs)
        #expect(latency >= 240 && latency <= 260)
    }
    
    @Test func testServerHealthBootstrapRestoresSnapshot() async throws {
        let storage = try Storage.Facade(configuration: .memory)
        let repository = await storage.serverHealth
        let endpoint = try #require(URL(string: "wss://example.org:50002"))
        let monitor = Network.Wallet.FulcrumPool.ServerHealth(repository: repository)
        
        _ = try await monitor.recordSuccess(for: endpoint, latency: 0.18)
        
        let restored = Network.Wallet.FulcrumPool.ServerHealth(repository: repository)
        let snapshot = try await restored.bootstrap(for: endpoint)
        let restoredLatency = try #require(snapshot?.latency)
        #expect(abs(restoredLatency - 0.18) < 0.02)
    }
    
    @Test func testServerHealthIncrementsFailuresWithBackoff() async throws {
        let storage = try Storage.Facade(configuration: .memory)
        let repository = await storage.serverHealth
        let monitor = Network.Wallet.FulcrumPool.ServerHealth(repository: repository)
        let endpoint = try #require(URL(string: "wss://example.org:50002"))
        
        let now = Date()
        let firstRetry = now.addingTimeInterval(3)
        let secondRetry = now.addingTimeInterval(9)
        let first = try await monitor.recordFailure(for: endpoint, retryAt: firstRetry)
        let second = try await monitor.recordFailure(for: endpoint, retryAt: secondRetry)
        
        #expect(first.failures == 1)
        #expect(second.failures == 2)
        
        let firstQuarantine = try #require(first.quarantineUntil)
        let secondQuarantine = try #require(second.quarantineUntil)
        #expect(firstQuarantine >= firstRetry)
        #expect(secondQuarantine >= secondRetry)
        
        let stored = try await repository.history(endpoint)
        #expect(stored?.failures == 2)
    }
    
    @Test func testRetryBudgetDelaysAfterBurst() {
        let configuration = Network.Wallet.FulcrumPool.Retry.Configuration.Budget(maximumAttempts: 2,
                                                                                  replenishmentInterval: 4)
        var budget = Network.Wallet.FulcrumPool.Retry(configuration: configuration,
                                                      now: Date(timeIntervalSince1970: 0))
        
        let origin = Date(timeIntervalSince1970: 0)
        #expect(budget.nextDelay(now: origin) == 0)
        #expect(budget.nextDelay(now: origin) == 0)
        
        let throttledDelay = budget.nextDelay(now: origin)
        #expect(abs(throttledDelay - 4) < 0.01)
        
        let resumed = budget.nextDelay(now: origin.addingTimeInterval(throttledDelay))
        #expect(resumed == 0)
    }
    
    @Test func testRoleSelectionPrefersLowestLatency() {
        let now = Date()
        let metrics: [Network.Wallet.FulcrumPool.RoleMetrics] = [
            .init(index: 0, nextRetry: now, lastLatency: 0.35),
            .init(index: 1, nextRetry: now, lastLatency: 0.22),
            .init(index: 2, nextRetry: now.addingTimeInterval(30), lastLatency: 0.18)
        ]
        
        let roles = Network.Wallet.FulcrumPool.determineRoles(for: metrics, now: now, preferredPrimary: nil)
        
        #expect(roles.primary == 1)
        #expect(roles.standby == 0)
    }
    
    @Test func testRoleSelectionUsesPreferredPrimaryWhenHealthy() {
        let now = Date()
        let metrics: [Network.Wallet.FulcrumPool.RoleMetrics] = [
            .init(index: 0, nextRetry: now, lastLatency: 0.45),
            .init(index: 1, nextRetry: now, lastLatency: 0.18)
        ]
        
        let roles = Network.Wallet.FulcrumPool.determineRoles(for: metrics, now: now, preferredPrimary: 0)
        
        #expect(roles.primary == 0)
        #expect(roles.standby == 1)
    }
    
    @Test func testRoleSelectionPromotesStandbyWhenPreferredIsQuarantined() {
        let now = Date()
        let metrics: [Network.Wallet.FulcrumPool.RoleMetrics] = [
            .init(index: 0, nextRetry: now.addingTimeInterval(60), lastLatency: 0.12),
            .init(index: 1, nextRetry: now, lastLatency: 0.28),
            .init(index: 2, nextRetry: now, lastLatency: 0.31)
        ]
        
        let roles = Network.Wallet.FulcrumPool.determineRoles(for: metrics, now: now, preferredPrimary: 0)
        
        #expect(roles.primary == 1)
        #expect(roles.standby == 2)
    }
}
