import Foundation
import Testing
@testable import OpalBase

@Suite("Network Wallet Subscription Hub", .tags(.unit, .network))
struct NetworkWalletSubscriptionHubSuite {
    @Test("coalesces duplicated updates while preserving ordering", .tags(.unit, .network))
    func coalescesDuplicatesPreservingOrdering() async throws {
        
    }

    @Test("replays persisted state when upstream drops updates", .tags(.unit, .network))
    func replaysPersistedStateWhenUpstreamDropsUpdates() async throws {
        
    }
}
