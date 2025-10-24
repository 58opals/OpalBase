import Foundation
import Testing
@testable import OpalBase

@Suite("Subscription Hub Live Fulcrum Integration", .tags(.integration, .wallet, .network))
struct SubscriptionHubFulcrumIntegrationTests {
    private enum LiveFulcrumTestError: Swift.Error, Sendable {
        case timedOut
        case streamEndedPrematurely
        case missingFulcrumServers
        case primaryRoleUnavailable
    }
    
    private static let publicFulcrumEndpoints: [String] = [
        "wss://bch.imaginary.cash:50004",
        "wss://bch.soul-dev.com:50004",
        "wss://bch.loping.net:50004"
    ]
    
    @Test("bundled Fulcrum servers surface live subscription events")
    func bundledFulcrumServersSurfaceLiveEvents() async throws {
        let telemetry = Telemetry(isEnabled: false, handlers: [])
        let hub = Network.Wallet.SubscriptionHub(telemetry: telemetry)
        let pool = try await Network.Wallet.FulcrumPool()
        //let pool = try await Network.Wallet.FulcrumPool(urls: Self.publicFulcrumEndpoints)
        let node = try await pool.acquireNode()
        let address = try Address("bitcoincash:qpm2qsznhks23z7629mms6s4cwef74vcwvy22gdx6a")
        let consumerID = UUID()
        let stream = try await hub.makeStream(for: [address], using: node, consumerID: consumerID)
        defer { Task { await hub.remove(consumerID: consumerID) } }
        
        let event = try await waitForFirstEvent(in: stream)
        
        let status = await pool.currentStatus
        let roles = try await waitForAssignedRoles(in: pool)
        
        #expect(status == .online)
        #expect(roles.primary.scheme?.lowercased() == "wss")
        #expect(event.address == address)
        #expect(event.sequence >= 1)
        #expect(event.replayFlag == false)
        #expect(event.status?.isEmpty == false)
        
        let balance = try await node.balance(for: address, includeUnconfirmed: true)
        
        print(status)
        print(roles)
        print(event)
        
        #expect(balance.uint64 <= 21_000_000 * 100_000_000)
    }
    
    private func waitForAssignedRoles(
        in pool: Network.Wallet.FulcrumPool,
        timeout: Duration = .seconds(30)
    ) async throws -> (primary: URL, standby: URL?) {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        
        while clock.now < deadline {
            let roles = await pool.describeRoles()
            if let primary = roles.primary {
                return (primary, roles.standby)
            }
            try await clock.sleep(for: .milliseconds(200))
        }
        
        throw LiveFulcrumTestError.primaryRoleUnavailable
    }
    
    private func waitForFirstEvent(
        in stream: Network.Wallet.SubscriptionHub.Stream,
        timeoutNanoseconds: UInt64 = 30_000_000_000
    ) async throws -> Network.Wallet.SubscriptionHub.Notification.Event {
        try await withThrowingTaskGroup(of: Network.Wallet.SubscriptionHub.Notification.Event.self) { group in
            group.addTask {
                var iterator = stream.eventStream.makeAsyncIterator()
                guard let event = try await iterator.next() else {
                    throw LiveFulcrumTestError.streamEndedPrematurely
                }
                return event
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw LiveFulcrumTestError.timedOut
            }
            
            do {
                guard let event = try await group.next() else {
                    group.cancelAll()
                    throw LiveFulcrumTestError.streamEndedPrematurely
                }
                group.cancelAll()
                return event
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}
