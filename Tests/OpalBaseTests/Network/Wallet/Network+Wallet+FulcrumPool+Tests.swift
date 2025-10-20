import Foundation
import Testing
@testable import OpalBase

@Suite("Fulcrum Pool Role Determination", .tags(.unit, .wallet, .network))
struct NetworkWalletFulcrumPoolRoleTests {
    @Test("determineRoles orders available servers by ascending latency")
    func determineRolesPrefersLowestLatencyAvailable() {
        let now = Date()
        let metrics = [
            Network.Wallet.FulcrumPool.RoleMetrics(index: 0, nextRetry: now, lastLatency: 0.3),
            Network.Wallet.FulcrumPool.RoleMetrics(index: 1, nextRetry: now, lastLatency: 0.1),
            Network.Wallet.FulcrumPool.RoleMetrics(index: 2, nextRetry: now, lastLatency: 0.5)
        ]
        
        let roles = Network.Wallet.FulcrumPool.determineRoles(for: metrics, now: now, preferredPrimary: nil)
        
        #expect(roles.primary == 1)
        #expect(roles.standby == 0)
    }
    
    @Test("determineRoles elevates preferred primary when the server is eligible")
    func determineRolesHonorsPreferredPrimaryWhenAvailable() {
        let now = Date()
        let metrics = [
            Network.Wallet.FulcrumPool.RoleMetrics(index: 0, nextRetry: now, lastLatency: 0.4),
            Network.Wallet.FulcrumPool.RoleMetrics(index: 1, nextRetry: now, lastLatency: 0.05),
            Network.Wallet.FulcrumPool.RoleMetrics(index: 2, nextRetry: now, lastLatency: 0.2)
        ]
        
        let roles = Network.Wallet.FulcrumPool.determineRoles(for: metrics, now: now, preferredPrimary: 0)
        
        #expect(roles.primary == 0)
        #expect(roles.standby == 1)
    }
    
    @Test("determineRoles falls back to deferred servers when none are immediately available")
    func determineRolesUsesDeferredWhenNecessary() {
        let now = Date()
        let metrics = [
            Network.Wallet.FulcrumPool.RoleMetrics(index: 0, nextRetry: now.addingTimeInterval(90), lastLatency: 0.15),
            Network.Wallet.FulcrumPool.RoleMetrics(index: 1, nextRetry: now.addingTimeInterval(30), lastLatency: 0.25),
            Network.Wallet.FulcrumPool.RoleMetrics(index: 2, nextRetry: now.addingTimeInterval(45), lastLatency: 0.05)
        ]
        
        let roles = Network.Wallet.FulcrumPool.determineRoles(for: metrics, now: now, preferredPrimary: nil)
        
        #expect(roles.primary == 1)
        #expect(roles.standby == 2)
    }
    
    @Test("determineRoles uses deferred candidates to populate standby when only one server is ready")
    func determineRolesPopulatesStandbyFromDeferredServers() {
        let now = Date()
        let metrics = [
            Network.Wallet.FulcrumPool.RoleMetrics(index: 0, nextRetry: now, lastLatency: 0.12),
            Network.Wallet.FulcrumPool.RoleMetrics(index: 1, nextRetry: now.addingTimeInterval(15), lastLatency: 0.04),
            Network.Wallet.FulcrumPool.RoleMetrics(index: 2, nextRetry: now.addingTimeInterval(45), lastLatency: nil)
        ]
        
        let roles = Network.Wallet.FulcrumPool.determineRoles(for: metrics, now: now, preferredPrimary: nil)
        
        #expect(roles.primary == 0)
        #expect(roles.standby == 1)
    }
}
