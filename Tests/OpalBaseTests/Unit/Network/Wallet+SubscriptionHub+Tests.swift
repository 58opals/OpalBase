import Foundation
import Testing
import SwiftFulcrum
@testable import OpalBase

@Suite("Network Wallet Subscription Hub", .tags(.network))
struct NetworkWalletSubscriptionHubSuite {
    @Test("coalesces duplicated updates while preserving ordering", .tags(.unit, .network))
    func coalescesDuplicatesPreservingOrdering() async throws {
        let configuration = Network.Wallet.SubscriptionHub.Configuration(
            debounceInterval: .milliseconds(10),
            maxDebounceInterval: .milliseconds(50),
            maxBatchSize: 64,
            serviceLevelObjective: .init(
                targetFanOutLatency: .milliseconds(40),
                maxFanOutLatency: .milliseconds(120),
                minimumThroughputPerSecond: 10
            )
        )
        let clock = ContinuousClock()
        let testAddress = try Address("bitcoincash:qp88maay77k0ug7x7kfs9zsy32r84p3t0un4ca44u9")
        var generator = SystemRandomNumberGenerator()
        let statusPool: [String?] = ["status0", "status1", "status2", nil]
        
        for _ in 0..<128 {
            var queue = Network.Wallet.SubscriptionHub.AddressQueue()
            let length = Int.random(in: 1...32, using: &generator)
            var statuses: [String?] = []
            for _ in 0..<length {
                let index = Int.random(in: 0..<statusPool.count, using: &generator)
                let status = statusPool[index]
                statuses.append(status)
                _ = queue.enqueue(status: status,
                                  replayFlag: false,
                                  clock: clock,
                                  configuration: configuration)
            }
            
            let optionalBatch = queue.flush(address: testAddress, flushedInstant: clock.now)
            #expect(optionalBatch != nil)
            guard let batch = optionalBatch else { continue }
            
            var expected: [String?] = []
            for status in statuses {
                if let last = expected.last, last == status {
                    expected[expected.count - 1] = status
                } else {
                    expected.append(status)
                }
            }
            
            #expect(batch.events.map(\.status) == expected)
            #expect(batch.events.allSatisfy { $0.replayFlag == false })
            for (index, event) in batch.events.enumerated() {
                #expect(event.sequence == UInt64(index + 1))
            }
            #expect(queue.lastStatus == expected.last)
            #expect(queue.pendingItems.isEmpty)
        }
    }
    
    @Test("guarantees ordering invariants under replay failure injection", .tags(.unit, .network))
    func guaranteesOrderingInvariantsUnderReplayFailureInjection() async throws {
        let configuration = Network.Wallet.SubscriptionHub.Configuration(
            debounceInterval: .milliseconds(10),
            maxDebounceInterval: .milliseconds(50),
            maxBatchSize: 64,
            serviceLevelObjective: .init(
                targetFanOutLatency: .milliseconds(40),
                maxFanOutLatency: .milliseconds(120),
                minimumThroughputPerSecond: 10
            )
        )
        let clock = ContinuousClock()
        let testAddress = try Address("bitcoincash:qp8z9a7jv9ej845kzvxmaz45gunsgtg4k5646q64zv")
        var generator = SystemRandomNumberGenerator()
        let statusPool: [String?] = ["hot", "cold", "warm", nil]
        
        for _ in 0..<96 {
            var queue = Network.Wallet.SubscriptionHub.AddressQueue()
            let startingSequence = UInt64.random(in: 0...512, using: &generator)
            queue.lastSequence = startingSequence
            queue.lastStatus = statusPool.randomElement(using: &generator) ?? nil
            
            let length = Int.random(in: 1...24, using: &generator)
            var inputs: [(String?, Bool)] = []
            for _ in 0..<length {
                let statusIndex = Int.random(in: 0..<statusPool.count, using: &generator)
                let replay = Bool.random(using: &generator)
                let status = statusPool[statusIndex]
                inputs.append((status, replay))
                _ = queue.enqueue(status: status,
                                  replayFlag: replay,
                                  clock: clock,
                                  configuration: configuration)
            }
            
            let optionalBatch = queue.flush(address: testAddress, flushedInstant: clock.now)
            #expect(optionalBatch != nil)
            guard let batch = optionalBatch else { continue }
            
            var reduced: [(String?, Bool)] = []
            for element in inputs {
                if let last = reduced.last, last.0 == element.0 {
                    reduced[reduced.count - 1] = element
                } else {
                    reduced.append(element)
                }
            }
            
            let expectedStart = startingSequence + 1
            for (offset, event) in batch.events.enumerated() {
                #expect(event.sequence == expectedStart + UInt64(offset))
            }
            #expect(batch.events.map { $0.status } == reduced.map { $0.0 })
            #expect(batch.events.map { $0.replayFlag } == reduced.map { $0.1 })
            #expect(queue.lastStatus == reduced.last?.0)
            #expect(queue.pendingItems.isEmpty)
        }
    }
    
    @Test("streams initial status from Fulcrum", .tags(.integration, .network, .fulcrum, .slow))
    func streamsInitialStatusFromFulcrum() async throws {
        guard Environment.network, let endpoint = Environment.fulcrumURL else { return }
        
        let fulcrum = try await Fulcrum(url: endpoint)
        let node = Adapter.SwiftFulcrum.Node(fulcrum: fulcrum)
        let hub = Network.Wallet.SubscriptionHub(configuration: .standard)
        let consumerID = UUID()
        let address = try Address("bitcoincash:qqc7tchze85fvh2zyuz2zreul6l7q0crlun2s6uj9a")
        
        let stream = try await hub.makeStream(for: [address], using: node, consumerID: consumerID)
        
        enum Timeout: Swift.Error { case exceeded }
        let firstEvent: Network.Wallet.SubscriptionHub.Notification.Event? = try await withThrowingTaskGroup(of: Network.Wallet.SubscriptionHub.Notification.Event?.self) { group in
            group.addTask {
                var iterator = stream.eventStream.makeAsyncIterator()
                return try await iterator.next()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw Timeout.exceeded
            }
            guard let event = try await group.next() else { return nil }
            group.cancelAll()
            return event
        }
        
        #expect(firstEvent?.address == address)
        #expect((firstEvent?.sequence ?? 0) > 0)
        
        await hub.remove(consumerID: consumerID)
    }
}
